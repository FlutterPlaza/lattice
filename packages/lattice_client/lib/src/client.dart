import 'dart:math';
import 'dart:typed_data';

import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/lattice_protocol.dart';

import 'connection.dart';
import 'secure_storage.dart';
import 'session_manager.dart';

/// High-level client for the Lattice post-quantum Signal protocol.
///
/// Orchestrates registration, pre-key management, session initiation, and
/// session finalization by coordinating between the [Connection] (server API),
/// [SecureStorage] (local key persistence), and the protocol-level
/// [Registration], [Initiator], and [Responder] types.
class LatticeClient {
  /// Creates a [LatticeClient] for the given [userId].
  ///
  /// An optional [storage] and [crypto] provider can be supplied; they default
  /// to [InMemorySecureStorage] and the standard [CryptoProvider] respectively.
  LatticeClient({
    required this.userId,
    required this.connection,
    SecureStorage? storage,
    CryptoProvider? crypto,
  }) : storage = storage ?? InMemorySecureStorage(),
       crypto = crypto ?? const CryptoProvider(),
       sessions = SessionManager();

  /// The local user's identity string.
  final String userId;

  /// The server connection layer.
  final Connection connection;

  /// Secure storage for identity and pre-keys.
  final SecureStorage storage;

  /// Cryptographic provider for KEM, SIG, Ext, and PRF primitives.
  final CryptoProvider crypto;

  /// Manager for active sessions.
  final SessionManager sessions;

  /// The size (in bytes) of the shared seed for the randomness extractor.
  static const int seedSize = 32;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Registers this user: generates a long-term key pair, stores it locally,
  /// and registers the public key with the server.
  Future<void> register() async {
    final reg = Registration(crypto);
    final result = reg.generate();
    await storage.saveIdentity(userId, result.publicKey, result.secretKey);
    await connection.register(userId, result.publicKey.serialize());
  }

  // ---------------------------------------------------------------------------
  // Pre-key management
  // ---------------------------------------------------------------------------

  /// Generates and uploads a new ephemeral pre-key to the server.
  ///
  /// The secret half of the pre-key is stored locally; only the public bundle
  /// is sent to the server.
  ///
  /// Throws [StateError] if the user has not been registered yet.
  Future<void> uploadPreKey() async {
    final publicKey = await storage.getPublicKey(userId);
    final secretKey = await storage.getSecretKey(userId);
    if (publicKey == null || secretKey == null) {
      throw StateError('Must register before uploading pre-keys');
    }

    final initiator = Initiator(crypto);
    final result = initiator.uploadPreKey(lpkA: publicKey, lskA: secretKey);
    await storage.savePreKey(userId, result.preKey);
    await connection.uploadPreKey(userId, result.bundle.serialize());
  }

  // ---------------------------------------------------------------------------
  // Session initiation (responder / Bob side)
  // ---------------------------------------------------------------------------

  /// Initiates a session with [peerId] by fetching their pre-key bundle from
  /// the server, performing the responder (Bob) side of the SC-AKE handshake,
  /// and sending the resulting key-exchange message.
  ///
  /// The seed for the randomness extractor is generated locally and encoded
  /// alongside the key-exchange message so that the peer can reconstruct the
  /// same session key.
  ///
  /// Returns the established [Session].
  ///
  /// Throws [StateError] if the local user is not registered or the peer has
  /// no pre-key bundle available.
  Future<Session> initiateSession(String peerId) async {
    final bundleData = await connection.fetchPreKey(peerId);
    if (bundleData == null) {
      throw StateError('No pre-key available for $peerId');
    }

    final bundle = PreKeyBundle.deserialize(bundleData);

    final publicKey = await storage.getPublicKey(userId);
    final secretKey = await storage.getSecretKey(userId);
    if (publicKey == null || secretKey == null) {
      throw StateError('Not registered');
    }

    final seed = _generateSeed();

    final responder = Responder(crypto);
    final result = responder.createSession(
      identityA: peerId,
      identityB: userId,
      bundleA: bundle,
      lpkB: publicKey,
      lskB: secretKey,
      seed: seed,
    );

    // Encode seed + Bob's lpk + key exchange message for transmission.
    final payload = _encodeSessionPayload(
      seed: seed,
      senderPublicKey: publicKey.serialize(),
      message: result.message.serialize(),
    );
    await connection.sendMessage(peerId, userId, payload);

    final session = Session(
      sessionId: result.sessionId,
      sessionKey: result.sessionKey,
      localIdentity: userId,
      remoteIdentity: peerId,
    );
    sessions.addSession(peerId, session);
    return session;
  }

  // ---------------------------------------------------------------------------
  // Session finalization (initiator / Alice side)
  // ---------------------------------------------------------------------------

  /// Fetches pending key-exchange messages and finalizes sessions as the
  /// initiator (Alice).
  ///
  /// Returns a list of newly established [Session] objects.
  ///
  /// Throws [StateError] if the local user is not registered or has no
  /// pre-key available.
  Future<List<Session>> respondToSessions() async {
    final publicKey = await storage.getPublicKey(userId);
    final secretKey = await storage.getSecretKey(userId);
    if (publicKey == null || secretKey == null) {
      throw StateError('Not registered');
    }

    final preKey = await storage.getPreKey(userId);
    if (preKey == null) {
      throw StateError('No pre-key available');
    }

    final messages = await connection.fetchMessages(userId);
    final newSessions = <Session>[];

    for (final msg in messages) {
      final (:seed, :senderPublicKey, :message) = _decodeSessionPayload(
        msg.messageData,
      );

      final peerLpk = LongTermPublicKey.deserialize(senderPublicKey);
      final exchangeMsg = KeyExchangeMessage.deserialize(message);

      final initiator = Initiator(crypto);
      final result = initiator.finalizeSession(
        identityA: userId,
        identityB: msg.senderId,
        lpkA: publicKey,
        lpkB: peerLpk,
        lskA: secretKey,
        preKey: preKey,
        message: exchangeMsg,
        seed: seed,
      );

      final session = Session(
        sessionId: result.sessionId,
        sessionKey: result.sessionKey,
        localIdentity: userId,
        remoteIdentity: msg.senderId,
      );
      sessions.addSession(msg.senderId, session);
      newSessions.add(session);
    }

    // Consume the pre-key after processing messages.
    if (newSessions.isNotEmpty) {
      await storage.removePreKey(userId);
    }

    return newSessions;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the underlying server connection.
  void close() {
    connection.close();
  }

  // ---------------------------------------------------------------------------
  // Payload encoding helpers
  // ---------------------------------------------------------------------------

  /// Generates a cryptographically secure random seed.
  Uint8List _generateSeed() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(seedSize, (_) => random.nextInt(256)),
    );
  }

  /// Encodes the session payload sent from the responder to the initiator.
  ///
  /// Layout:
  /// ```
  /// [32 bytes seed]
  /// [4 bytes: big-endian length of sender lpk]
  /// [N bytes: serialized sender lpk]
  /// [remaining bytes: serialized KeyExchangeMessage]
  /// ```
  static Uint8List _encodeSessionPayload({
    required Uint8List seed,
    required Uint8List senderPublicKey,
    required Uint8List message,
  }) {
    final builder = BytesBuilder(copy: false);
    builder.add(seed);
    // 4-byte big-endian length prefix for the public key.
    final len = senderPublicKey.length;
    builder.addByte((len >> 24) & 0xFF);
    builder.addByte((len >> 16) & 0xFF);
    builder.addByte((len >> 8) & 0xFF);
    builder.addByte(len & 0xFF);
    builder.add(senderPublicKey);
    builder.add(message);
    return builder.takeBytes();
  }

  /// Decodes a session payload encoded by [_encodeSessionPayload].
  static ({Uint8List seed, Uint8List senderPublicKey, Uint8List message})
  _decodeSessionPayload(Uint8List data) {
    var offset = 0;

    // Read 32-byte seed.
    final seed = Uint8List.fromList(data.sublist(offset, offset + seedSize));
    offset += seedSize;

    // Read 4-byte big-endian length of sender public key.
    final lpkLen =
        (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    offset += 4;

    // Read sender public key.
    final senderPublicKey = Uint8List.fromList(
      data.sublist(offset, offset + lpkLen),
    );
    offset += lpkLen;

    // Remaining bytes are the serialized KeyExchangeMessage.
    final message = Uint8List.fromList(data.sublist(offset));

    return (seed: seed, senderPublicKey: senderPublicKey, message: message);
  }
}
