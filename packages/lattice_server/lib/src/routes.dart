import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'storage.dart';

/// API route handlers for the Lattice key distribution server.
///
/// All endpoints exchange JSON payloads. Cryptographic material is encoded
/// as base64 strings within the JSON bodies.
class Routes {
  /// Creates the route handlers backed by the given [storage].
  Routes(this.storage) : startTime = DateTime.now();

  /// The storage backend used by all route handlers.
  final Storage storage;

  /// The time the server started (used for uptime calculations).
  final DateTime startTime;

  /// The current protocol version string.
  static const String version = '0.1.0';

  /// Returns the configured [Router] with all API endpoints.
  Router get router {
    final router = Router();

    // Registration.
    router.post('/api/v1/register', _register);

    // Pre-key bundle management.
    router.post('/api/v1/prekeys', _uploadPreKey);
    router.get('/api/v1/prekeys/<userId>', _getPreKey);

    // Message delivery.
    router.post('/api/v1/messages/<userId>', _sendMessage);
    router.get('/api/v1/messages/<userId>', _getMessages);

    // Operational.
    router.get('/api/v1/health', _health);
    router.get('/api/v1/metrics', _metrics);

    return router;
  }

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// POST /api/v1/register
  ///
  /// Body: `{"userId": "...", "publicKey": "<base64>"}`
  ///
  /// Registers a user with their long-term public key.
  Future<Response> _register(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final userId = json['userId'] as String?;
    final publicKeyB64 = json['publicKey'] as String?;

    if (userId == null || userId.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty userId'});
    }
    if (publicKeyB64 == null || publicKeyB64.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty publicKey'});
    }

    final publicKeyData = base64Decode(publicKeyB64);

    await storage.registerUser(
      UserRecord(
        userId: userId,
        publicKeyData: Uint8List.fromList(publicKeyData),
      ),
    );

    return _jsonResponse(201, {'status': 'registered', 'userId': userId});
  }

  // ---------------------------------------------------------------------------
  // Pre-key bundles
  // ---------------------------------------------------------------------------

  /// POST /api/v1/prekeys
  ///
  /// Body: `{"userId": "...", "bundle": "<base64>"}`
  ///
  /// Uploads (or replaces) a signed pre-key bundle.
  Future<Response> _uploadPreKey(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final userId = json['userId'] as String?;
    final bundleB64 = json['bundle'] as String?;

    if (userId == null || userId.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty userId'});
    }
    if (bundleB64 == null || bundleB64.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty bundle'});
    }

    final bundleData = base64Decode(bundleB64);

    await storage.storePreKey(
      PreKeyRecord(userId: userId, bundleData: Uint8List.fromList(bundleData)),
    );

    return _jsonResponse(200, {'status': 'stored', 'userId': userId});
  }

  /// `GET /api/v1/prekeys/<userId>`
  ///
  /// Response: `{"userId": "...", "bundle": "<base64>"}`
  ///
  /// Fetches and removes the pre-key bundle for a user.
  Future<Response> _getPreKey(Request request, String userId) async {
    final record = await storage.getPreKey(userId);
    if (record == null) {
      return _jsonResponse(404, {
        'error': 'No pre-key bundle for user "$userId"',
      });
    }

    // Remove the pre-key after serving it (one-time use).
    await storage.removePreKey(userId);

    return _jsonResponse(200, {
      'userId': record.userId,
      'bundle': base64Encode(record.bundleData),
    });
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// `POST /api/v1/messages/<userId>`
  ///
  /// Body: `{"senderId": "...", "message": "<base64>"}`
  ///
  /// Sends a key exchange message to the specified user.
  Future<Response> _sendMessage(Request request, String userId) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final senderId = json['senderId'] as String?;
    final messageB64 = json['message'] as String?;

    if (senderId == null || senderId.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty senderId'});
    }
    if (messageB64 == null || messageB64.isEmpty) {
      return _jsonResponse(400, {'error': 'Missing or empty message'});
    }

    final messageData = base64Decode(messageB64);

    await storage.storeMessage(
      MessageRecord(
        recipientId: userId,
        senderId: senderId,
        messageData: Uint8List.fromList(messageData),
      ),
    );

    return _jsonResponse(200, {'status': 'delivered'});
  }

  /// `GET /api/v1/messages/<userId>`
  ///
  /// Response: `{"messages": [{"senderId": "...", "message": "<base64>", "sentAt": "..."}]}`
  ///
  /// Fetches and clears all pending messages for the specified user.
  Future<Response> _getMessages(Request request, String userId) async {
    final messages = await storage.getMessages(userId);

    // Clear messages after retrieval.
    await storage.clearMessages(userId);

    final payload =
        messages
            .map(
              (m) => {
                'senderId': m.senderId,
                'message': base64Encode(m.messageData),
                'sentAt': m.sentAt.toIso8601String(),
              },
            )
            .toList();

    return _jsonResponse(200, {'messages': payload});
  }

  // ---------------------------------------------------------------------------
  // Operational
  // ---------------------------------------------------------------------------

  /// GET /api/v1/health
  ///
  /// Response: `{"status": "ok", "uptime": <seconds>, "version": "0.1.0"}`
  Future<Response> _health(Request request) async {
    final uptime = DateTime.now().difference(startTime).inSeconds;
    return _jsonResponse(200, {
      'status': 'ok',
      'uptime': uptime,
      'version': version,
    });
  }

  /// GET /api/v1/metrics
  ///
  /// Response: `{"users": <count>, "prekeys": <count>, "pendingMessages": <count>, "uptime": <seconds>}`
  ///
  /// Returns operational metrics only -- never exposes cryptographic material.
  Future<Response> _metrics(Request request) async {
    final uptime = DateTime.now().difference(startTime).inSeconds;
    return _jsonResponse(200, {
      'users': await storage.getUserCount(),
      'prekeys': await storage.getPreKeyCount(),
      'pendingMessages': await storage.getMessageCount(),
      'uptime': uptime,
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns a JSON [Response] with the given [statusCode] and [body] map.
  static Response _jsonResponse(int statusCode, Map<String, dynamic> body) =>
      Response(
        statusCode,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
}
