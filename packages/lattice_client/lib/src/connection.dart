import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Exception thrown when the server returns a non-success status code.
class LatticeApiException implements Exception {
  /// Creates a [LatticeApiException].
  const LatticeApiException(this.statusCode, this.message);

  /// The HTTP status code returned by the server.
  final int statusCode;

  /// The error message from the server (or a default).
  final String message;

  @override
  String toString() => 'LatticeApiException($statusCode): $message';
}

/// HTTP connection layer for the Lattice key distribution server.
///
/// All cryptographic material is base64-encoded within JSON payloads, matching
/// the server's REST API contract.
class Connection {
  /// Creates a [Connection] to the server at [baseUrl].
  ///
  /// An optional [client] can be injected for testing.
  Connection({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// The base URL of the Lattice server (e.g. `http://localhost:8080`).
  final String baseUrl;

  final http.Client _client;

  String? _authToken;

  /// Sets the Bearer token used for authenticated requests.
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Registers a user with the server.
  ///
  /// `POST /api/v1/register`
  /// Body: `{"userId": "...", "publicKey": "<base64>"}`
  Future<void> register(String userId, Uint8List publicKeyData) async {
    final body = jsonEncode({
      'userId': userId,
      'publicKey': base64Encode(publicKeyData),
    });
    await _post('/api/v1/register', body);
  }

  /// Uploads a signed pre-key bundle for [userId].
  ///
  /// `POST /api/v1/prekeys`
  /// Body: `{"userId": "...", "bundle": "<base64>"}`
  Future<void> uploadPreKey(String userId, Uint8List bundleData) async {
    final body = jsonEncode({
      'userId': userId,
      'bundle': base64Encode(bundleData),
    });
    await _post('/api/v1/prekeys', body);
  }

  /// Fetches and consumes the pre-key bundle for [userId].
  ///
  /// `GET /api/v1/prekeys/:userId`
  /// Returns `null` if no bundle is available (404).
  Future<Uint8List?> fetchPreKey(String userId) async {
    final response = await _get('/api/v1/prekeys/$userId');
    if (response.statusCode == 404) return null;
    _checkStatus(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final bundleB64 = json['bundle'] as String;
    return base64Decode(bundleB64);
  }

  /// Sends a key-exchange message to [recipientId].
  ///
  /// `POST /api/v1/messages/:userId`
  /// Body: `{"senderId": "...", "message": "<base64>"}`
  Future<void> sendMessage(
    String recipientId,
    String senderId,
    Uint8List messageData,
  ) async {
    final body = jsonEncode({
      'senderId': senderId,
      'message': base64Encode(messageData),
    });
    await _post('/api/v1/messages/$recipientId', body);
  }

  /// Fetches and clears all pending messages for [userId].
  ///
  /// `GET /api/v1/messages/:userId`
  /// Returns a list of `(senderId, messageData)` records.
  Future<List<({String senderId, Uint8List messageData})>> fetchMessages(
    String userId,
  ) async {
    final response = await _get('/api/v1/messages/$userId');
    _checkStatus(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = json['messages'] as List<dynamic>;
    return messages.map((dynamic m) {
      final map = m as Map<String, dynamic>;
      return (
        senderId: map['senderId'] as String,
        messageData: base64Decode(map['message'] as String),
      );
    }).toList();
  }

  /// Checks server health.
  ///
  /// `GET /api/v1/health`
  /// Returns the parsed JSON response body.
  Future<Map<String, dynamic>> health() async {
    final response = await _get('/api/v1/health');
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, String> get _headers {
    final headers = <String, String>{'content-type': 'application/json'};
    if (_authToken != null) {
      headers['authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<http.Response> _post(String path, String body) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _client.post(uri, headers: _headers, body: body);
    _checkStatus(response);
    return response;
  }

  Future<http.Response> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    return _client.get(uri, headers: _headers);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        message = json['error'] as String? ?? response.body;
      } on Object {
        message = response.body;
      }
      throw LatticeApiException(response.statusCode, message);
    }
  }
}
