import 'dart:convert';
import 'dart:typed_data';

import 'serverpod_storage.dart';

/// Template endpoint handlers for Serverpod integration.
///
/// These are designed to be used inside a Serverpod project's endpoint class.
/// Example usage in a Serverpod project:
///
/// ```dart
/// import 'package:serverpod/serverpod.dart';
/// import 'package:lattice_server_serverpod/lattice_server_serverpod.dart';
///
/// class LatticeEndpoint extends Endpoint {
///   final _handlers = ServerpodEndpointHandlers();
///
///   Future<Map<String, dynamic>> register(
///     Session session, String userId, String publicKeyBase64,
///   ) async {
///     final storage = ServerpodStorage(ServerpodDatabaseAdapter(session));
///     return _handlers.register(storage, userId, publicKeyBase64);
///   }
///   // ... other endpoints
/// }
/// ```
class ServerpodEndpointHandlers {
  /// Creates a [ServerpodEndpointHandlers] instance.
  ///
  /// Records [startTime] for uptime calculations in health and metrics
  /// responses.
  ServerpodEndpointHandlers() : startTime = DateTime.now();

  /// The time this handler set was created (used for uptime calculations).
  final DateTime startTime;

  /// The current protocol version string.
  static const String version = '0.1.0';

  /// Registers a user with their long-term public key.
  ///
  /// [publicKeyBase64] is the base64-encoded serialized public key.
  /// Throws [StateError] if the user is already registered.
  Future<Map<String, dynamic>> register(
    ServerpodStorage storage,
    String userId,
    String publicKeyBase64,
  ) async {
    final publicKeyData = Uint8List.fromList(base64Decode(publicKeyBase64));
    final existing = await storage.getUserPublicKey(userId);
    if (existing != null) {
      throw StateError('User $userId already registered');
    }
    await storage.registerUser(userId, publicKeyData);
    return {'status': 'registered', 'userId': userId};
  }

  /// Uploads (or replaces) a signed pre-key bundle.
  ///
  /// [bundleBase64] is the base64-encoded serialized [PreKeyBundle].
  Future<Map<String, dynamic>> uploadPreKey(
    ServerpodStorage storage,
    String userId,
    String bundleBase64,
  ) async {
    final bundleData = Uint8List.fromList(base64Decode(bundleBase64));
    await storage.storePreKey(userId, bundleData);
    return {'status': 'stored', 'userId': userId};
  }

  /// Fetches and removes the pre-key bundle for [userId].
  ///
  /// Returns `null` if no pre-key bundle is available.
  Future<Map<String, dynamic>?> getPreKey(
    ServerpodStorage storage,
    String userId,
  ) async {
    final bundleData = await storage.getPreKey(userId);
    if (bundleData == null) return null;

    // Remove the pre-key after serving it (one-time use).
    await storage.removePreKey(userId);

    return {'userId': userId, 'bundle': base64Encode(bundleData)};
  }

  /// Sends a key exchange message to the specified recipient.
  ///
  /// [messageBase64] is the base64-encoded serialized [KeyExchangeMessage].
  Future<Map<String, dynamic>> sendMessage(
    ServerpodStorage storage,
    String recipientId,
    String senderId,
    String messageBase64,
  ) async {
    final messageData = Uint8List.fromList(base64Decode(messageBase64));
    await storage.storeMessage(recipientId, senderId, messageData);
    return {'status': 'delivered'};
  }

  /// Fetches and clears all pending messages for [userId].
  Future<List<Map<String, dynamic>>> getMessages(
    ServerpodStorage storage,
    String userId,
  ) async {
    final messages = await storage.getMessages(userId);

    // Clear messages after retrieval.
    await storage.clearMessages(userId);

    return messages
        .map(
          (m) => <String, dynamic>{
            'senderId': m.senderId,
            'message': base64Encode(m.messageData),
            'sentAt': m.sentAt,
          },
        )
        .toList();
  }

  /// Returns a health check response.
  Map<String, dynamic> health() {
    final uptime = DateTime.now().difference(startTime).inSeconds;
    return {'status': 'ok', 'uptime': uptime, 'version': version};
  }

  /// Returns operational metrics.
  ///
  /// Never exposes cryptographic material.
  Future<Map<String, dynamic>> metrics(ServerpodStorage storage) async {
    final uptime = DateTime.now().difference(startTime).inSeconds;
    return {
      'users': await storage.getUserCount(),
      'prekeys': await storage.getPreKeyCount(),
      'pendingMessages': await storage.getMessageCount(),
      'uptime': uptime,
    };
  }
}
