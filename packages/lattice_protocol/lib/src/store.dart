import 'package:lattice_protocol/src/key_types.dart';
import 'package:lattice_protocol/src/session.dart';

/// Abstract identity store: manages long-term key pairs.
abstract class IdentityStore {
  /// Saves the long-term key pair for [userId].
  Future<void> saveIdentity(
    String userId,
    LongTermPublicKey publicKey,
    LongTermSecretKey secretKey,
  );

  /// Retrieves the long-term public key for [userId], or `null` if not found.
  Future<LongTermPublicKey?> getPublicKey(String userId);

  /// Retrieves the long-term secret key for [userId], or `null` if not found.
  Future<LongTermSecretKey?> getSecretKey(String userId);
}

/// Abstract pre-key store: manages ephemeral pre-keys.
abstract class PreKeyStore {
  /// Saves an ephemeral pre-key for [userId].
  Future<void> savePreKey(String userId, EphemeralPreKey preKey);

  /// Retrieves the ephemeral pre-key for [userId], or `null` if not found.
  Future<EphemeralPreKey?> getPreKey(String userId);

  /// Removes the ephemeral pre-key for [userId].
  Future<void> removePreKey(String userId);
}

/// Abstract session store: manages active sessions.
abstract class SessionStore {
  /// Saves a session keyed by [peerId].
  Future<void> saveSession(String peerId, Session session);

  /// Retrieves the session for [peerId], or `null` if not found.
  Future<Session?> getSession(String peerId);

  /// Retrieves all active sessions.
  Future<List<Session>> getAllSessions();

  /// Removes the session for [peerId].
  Future<void> removeSession(String peerId);
}

/// In-memory implementation of [IdentityStore] for testing.
class InMemoryIdentityStore implements IdentityStore {
  final Map<String, LongTermPublicKey> _publicKeys =
      <String, LongTermPublicKey>{};
  final Map<String, LongTermSecretKey> _secretKeys =
      <String, LongTermSecretKey>{};

  @override
  Future<void> saveIdentity(
    String userId,
    LongTermPublicKey publicKey,
    LongTermSecretKey secretKey,
  ) async {
    _publicKeys[userId] = publicKey;
    _secretKeys[userId] = secretKey;
  }

  @override
  Future<LongTermPublicKey?> getPublicKey(String userId) async {
    return _publicKeys[userId];
  }

  @override
  Future<LongTermSecretKey?> getSecretKey(String userId) async {
    return _secretKeys[userId];
  }
}

/// In-memory implementation of [PreKeyStore] for testing.
class InMemoryPreKeyStore implements PreKeyStore {
  final Map<String, EphemeralPreKey> _preKeys = <String, EphemeralPreKey>{};

  @override
  Future<void> savePreKey(String userId, EphemeralPreKey preKey) async {
    _preKeys[userId] = preKey;
  }

  @override
  Future<EphemeralPreKey?> getPreKey(String userId) async {
    return _preKeys[userId];
  }

  @override
  Future<void> removePreKey(String userId) async {
    _preKeys.remove(userId);
  }
}

/// In-memory implementation of [SessionStore] for testing.
class InMemorySessionStore implements SessionStore {
  final Map<String, Session> _sessions = <String, Session>{};

  @override
  Future<void> saveSession(String peerId, Session session) async {
    _sessions[peerId] = session;
  }

  @override
  Future<Session?> getSession(String peerId) async {
    return _sessions[peerId];
  }

  @override
  Future<List<Session>> getAllSessions() async {
    return List<Session>.unmodifiable(_sessions.values);
  }

  @override
  Future<void> removeSession(String peerId) async {
    _sessions.remove(peerId);
  }
}
