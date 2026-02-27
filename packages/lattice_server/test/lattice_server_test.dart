import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lattice_server/lattice_server.dart';
import 'package:shelf/shelf.dart' hide Middleware;
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Storage tests
  // ---------------------------------------------------------------------------
  group('InMemoryStorage', () {
    late InMemoryStorage storage;

    setUp(() {
      storage = InMemoryStorage();
    });

    group('users', () {
      test('registerUser stores and retrieves a user', () async {
        final record = UserRecord(
          userId: 'alice',
          publicKeyData: Uint8List.fromList([1, 2, 3]),
        );
        await storage.registerUser(record);

        final fetched = await storage.getUser('alice');
        expect(fetched, isNotNull);
        expect(fetched!.userId, equals('alice'));
        expect(fetched.publicKeyData, equals([1, 2, 3]));
      });

      test('registerUser throws on duplicate userId', () async {
        final record = UserRecord(
          userId: 'alice',
          publicKeyData: Uint8List.fromList([1, 2, 3]),
        );
        await storage.registerUser(record);

        expect(() => storage.registerUser(record), throwsA(isA<StateError>()));
      });

      test('getUser returns null for unknown user', () async {
        final result = await storage.getUser('unknown');
        expect(result, isNull);
      });

      test('getUserCount returns correct count', () async {
        expect(await storage.getUserCount(), equals(0));
        await storage.registerUser(
          UserRecord(userId: 'alice', publicKeyData: Uint8List(0)),
        );
        expect(await storage.getUserCount(), equals(1));
        await storage.registerUser(
          UserRecord(userId: 'bob', publicKeyData: Uint8List(0)),
        );
        expect(await storage.getUserCount(), equals(2));
      });
    });

    group('prekeys', () {
      test('storePreKey and getPreKey round-trip', () async {
        final record = PreKeyRecord(
          userId: 'alice',
          bundleData: Uint8List.fromList([10, 20, 30]),
        );
        await storage.storePreKey(record);

        final fetched = await storage.getPreKey('alice');
        expect(fetched, isNotNull);
        expect(fetched!.bundleData, equals([10, 20, 30]));
      });

      test('storePreKey replaces existing prekey', () async {
        await storage.storePreKey(
          PreKeyRecord(userId: 'alice', bundleData: Uint8List.fromList([1])),
        );
        await storage.storePreKey(
          PreKeyRecord(userId: 'alice', bundleData: Uint8List.fromList([2])),
        );

        final fetched = await storage.getPreKey('alice');
        expect(fetched!.bundleData, equals([2]));
      });

      test('getPreKey returns null for unknown user', () async {
        final result = await storage.getPreKey('unknown');
        expect(result, isNull);
      });

      test('removePreKey removes the prekey', () async {
        await storage.storePreKey(
          PreKeyRecord(userId: 'alice', bundleData: Uint8List(0)),
        );
        await storage.removePreKey('alice');
        expect(await storage.getPreKey('alice'), isNull);
      });

      test('getPreKeyCount returns correct count', () async {
        expect(await storage.getPreKeyCount(), equals(0));
        await storage.storePreKey(
          PreKeyRecord(userId: 'alice', bundleData: Uint8List(0)),
        );
        expect(await storage.getPreKeyCount(), equals(1));
      });
    });

    group('messages', () {
      test('storeMessage and getMessages round-trip', () async {
        final record = MessageRecord(
          recipientId: 'alice',
          senderId: 'bob',
          messageData: Uint8List.fromList([100, 200]),
        );
        await storage.storeMessage(record);

        final messages = await storage.getMessages('alice');
        expect(messages, hasLength(1));
        expect(messages.first.senderId, equals('bob'));
        expect(messages.first.messageData, equals([100, 200]));
      });

      test('getMessages returns empty list for unknown user', () async {
        final result = await storage.getMessages('unknown');
        expect(result, isEmpty);
      });

      test('multiple messages for same recipient', () async {
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'bob',
            messageData: Uint8List.fromList([1]),
          ),
        );
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'charlie',
            messageData: Uint8List.fromList([2]),
          ),
        );

        final messages = await storage.getMessages('alice');
        expect(messages, hasLength(2));
      });

      test('clearMessages removes all messages for user', () async {
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'bob',
            messageData: Uint8List(0),
          ),
        );
        await storage.clearMessages('alice');
        expect(await storage.getMessages('alice'), isEmpty);
      });

      test('getMessageCount returns total across all recipients', () async {
        expect(await storage.getMessageCount(), equals(0));
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'bob',
            messageData: Uint8List(0),
          ),
        );
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'charlie',
            senderId: 'bob',
            messageData: Uint8List(0),
          ),
        );
        expect(await storage.getMessageCount(), equals(2));
      });
    });
  });

  group('FileStorage', () {
    late Directory tempDir;
    late FileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lattice_test_');
      storage = FileStorage(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('registerUser persists and retrieves a user', () async {
      await storage.registerUser(
        UserRecord(
          userId: 'alice',
          publicKeyData: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final fetched = await storage.getUser('alice');
      expect(fetched, isNotNull);
      expect(fetched!.userId, equals('alice'));
      expect(fetched.publicKeyData, equals([1, 2, 3]));
    });

    test('registerUser throws on duplicate', () async {
      await storage.registerUser(
        UserRecord(userId: 'alice', publicKeyData: Uint8List(0)),
      );
      expect(
        () => storage.registerUser(
          UserRecord(userId: 'alice', publicKeyData: Uint8List(0)),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('storePreKey and getPreKey round-trip', () async {
      await storage.storePreKey(
        PreKeyRecord(userId: 'alice', bundleData: Uint8List.fromList([5, 6])),
      );
      final fetched = await storage.getPreKey('alice');
      expect(fetched, isNotNull);
      expect(fetched!.bundleData, equals([5, 6]));
    });

    test('storeMessage and getMessages round-trip', () async {
      await storage.storeMessage(
        MessageRecord(
          recipientId: 'alice',
          senderId: 'bob',
          messageData: Uint8List.fromList([7, 8]),
        ),
      );
      final messages = await storage.getMessages('alice');
      expect(messages, hasLength(1));
      expect(messages.first.senderId, equals('bob'));
    });

    test('getUserCount, getPreKeyCount, getMessageCount', () async {
      expect(await storage.getUserCount(), equals(0));
      expect(await storage.getPreKeyCount(), equals(0));
      expect(await storage.getMessageCount(), equals(0));

      await storage.registerUser(
        UserRecord(userId: 'alice', publicKeyData: Uint8List(0)),
      );
      await storage.storePreKey(
        PreKeyRecord(userId: 'alice', bundleData: Uint8List(0)),
      );
      await storage.storeMessage(
        MessageRecord(
          recipientId: 'alice',
          senderId: 'bob',
          messageData: Uint8List(0),
        ),
      );

      expect(await storage.getUserCount(), equals(1));
      expect(await storage.getPreKeyCount(), equals(1));
      expect(await storage.getMessageCount(), equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Route tests
  // ---------------------------------------------------------------------------
  group('Routes', () {
    late InMemoryStorage storage;
    late Handler handler;

    setUp(() {
      storage = InMemoryStorage();
      final routes = Routes(storage);
      handler = const Pipeline()
          .addMiddleware(Middleware.errorHandler())
          .addHandler(routes.router.call);
    });

    group('POST /api/v1/register', () {
      test('registers a new user', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/register'),
            body: jsonEncode({
              'userId': 'alice',
              'publicKey': base64Encode([1, 2, 3]),
            }),
          ),
        );

        expect(response.statusCode, equals(201));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], equals('registered'));
        expect(body['userId'], equals('alice'));

        // Verify in storage.
        final user = await storage.getUser('alice');
        expect(user, isNotNull);
      });

      test('returns 409 for duplicate registration', () async {
        Future<Response> makeRequest() async => handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/register'),
            body: jsonEncode({
              'userId': 'alice',
              'publicKey': base64Encode([1, 2, 3]),
            }),
          ),
        );

        await makeRequest();
        final response = await makeRequest();
        expect(response.statusCode, equals(409));
      });

      test('returns 400 for missing userId', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/register'),
            body: jsonEncode({
              'publicKey': base64Encode([1, 2, 3]),
            }),
          ),
        );
        expect(response.statusCode, equals(400));
      });

      test('returns 400 for missing publicKey', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/register'),
            body: jsonEncode({'userId': 'alice'}),
          ),
        );
        expect(response.statusCode, equals(400));
      });
    });

    group('POST /api/v1/prekeys', () {
      test('uploads a pre-key bundle', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/prekeys'),
            body: jsonEncode({
              'userId': 'alice',
              'bundle': base64Encode([10, 20, 30]),
            }),
          ),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], equals('stored'));

        final preKey = await storage.getPreKey('alice');
        expect(preKey, isNotNull);
        expect(preKey!.bundleData, equals([10, 20, 30]));
      });

      test('returns 400 for missing fields', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/prekeys'),
            body: jsonEncode({'userId': 'alice'}),
          ),
        );
        expect(response.statusCode, equals(400));
      });
    });

    group('GET /api/v1/prekeys/<userId>', () {
      test('fetches and removes pre-key bundle', () async {
        await storage.storePreKey(
          PreKeyRecord(
            userId: 'alice',
            bundleData: Uint8List.fromList([10, 20]),
          ),
        );

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/prekeys/alice')),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['userId'], equals('alice'));
        expect(base64Decode(body['bundle'] as String), equals([10, 20]));

        // Pre-key should be removed after fetch.
        final remaining = await storage.getPreKey('alice');
        expect(remaining, isNull);
      });

      test('returns 404 for unknown user', () async {
        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/prekeys/unknown')),
        );
        expect(response.statusCode, equals(404));
      });
    });

    group('POST /api/v1/messages/<userId>', () {
      test('sends a message to a user', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/messages/alice'),
            body: jsonEncode({
              'senderId': 'bob',
              'message': base64Encode([50, 60, 70]),
            }),
          ),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], equals('delivered'));

        final messages = await storage.getMessages('alice');
        expect(messages, hasLength(1));
        expect(messages.first.senderId, equals('bob'));
      });

      test('returns 400 for missing senderId', () async {
        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/messages/alice'),
            body: jsonEncode({
              'message': base64Encode([1]),
            }),
          ),
        );
        expect(response.statusCode, equals(400));
      });
    });

    group('GET /api/v1/messages/<userId>', () {
      test('fetches and clears messages', () async {
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'bob',
            messageData: Uint8List.fromList([1, 2]),
          ),
        );
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'charlie',
            messageData: Uint8List.fromList([3, 4]),
          ),
        );

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/messages/alice')),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        expect(messages, hasLength(2));
        expect(messages[0]['senderId'], equals('bob'));
        expect(messages[1]['senderId'], equals('charlie'));

        // Messages should be cleared after fetch.
        final remaining = await storage.getMessages('alice');
        expect(remaining, isEmpty);
      });

      test('returns empty list for user with no messages', () async {
        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/messages/alice')),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['messages'] as List<dynamic>, isEmpty);
      });
    });

    group('GET /api/v1/health', () {
      test('returns status ok with uptime and version', () async {
        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/health')),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], equals('ok'));
        expect(body['version'], equals('0.1.0'));
        expect(body['uptime'], isA<int>());
      });
    });

    group('GET /api/v1/metrics', () {
      test('returns counts and uptime', () async {
        await storage.registerUser(
          UserRecord(userId: 'alice', publicKeyData: Uint8List(0)),
        );
        await storage.storePreKey(
          PreKeyRecord(userId: 'alice', bundleData: Uint8List(0)),
        );
        await storage.storeMessage(
          MessageRecord(
            recipientId: 'alice',
            senderId: 'bob',
            messageData: Uint8List(0),
          ),
        );

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/metrics')),
        );

        expect(response.statusCode, equals(200));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['users'], equals(1));
        expect(body['prekeys'], equals(1));
        expect(body['pendingMessages'], equals(1));
        expect(body['uptime'], isA<int>());
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Middleware tests
  // ---------------------------------------------------------------------------
  group('Middleware', () {
    group('errorHandler', () {
      test('catches FormatException and returns 400', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.errorHandler())
            .addHandler((_) => throw const FormatException('bad input'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(400));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['error'], contains('bad input'));
      });

      test('catches StateError and returns 409', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.errorHandler())
            .addHandler((_) => throw StateError('conflict'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(409));
      });

      test('catches generic exceptions and returns 500', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.errorHandler())
            .addHandler((_) => throw Exception('oops'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(500));
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['error'], equals('Internal server error'));
      });
    });

    group('cors', () {
      test('adds CORS headers to responses', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.cors())
            .addHandler((_) => Response.ok('hello'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.headers['access-control-allow-origin'], equals('*'));
        expect(
          response.headers['access-control-allow-methods'],
          contains('GET'),
        );
      });

      test('handles OPTIONS preflight requests', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.cors())
            .addHandler((_) => Response.ok('hello'));

        final response = await handler(
          Request('OPTIONS', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(200));
        expect(response.headers['access-control-allow-origin'], equals('*'));
      });
    });

    group('authToken', () {
      test('rejects requests without Authorization header', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.authToken())
            .addHandler((_) => Response.ok('secret'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/prekeys/alice')),
        );
        expect(response.statusCode, equals(401));
      });

      test('accepts requests with valid Bearer token', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.authToken())
            .addHandler((_) => Response.ok('secret'));

        final response = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/api/v1/prekeys/alice'),
            headers: {'authorization': 'Bearer my-token-123'},
          ),
        );
        expect(response.statusCode, equals(200));
      });

      test('allows health endpoint without auth', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.authToken())
            .addHandler((_) => Response.ok('ok'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/health')),
        );
        expect(response.statusCode, equals(200));
      });

      test('allows metrics endpoint without auth', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.authToken())
            .addHandler((_) => Response.ok('ok'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/metrics')),
        );
        expect(response.statusCode, equals(200));
      });
    });

    group('rateLimit', () {
      test('allows requests under the limit', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.rateLimit(maxRequests: 5))
            .addHandler((_) => Response.ok('ok'));

        for (var i = 0; i < 5; i++) {
          final response = await handler(
            Request('GET', Uri.parse('http://localhost/test')),
          );
          expect(response.statusCode, equals(200));
        }
      });

      test('rejects requests over the limit', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.rateLimit(maxRequests: 2))
            .addHandler((_) => Response.ok('ok'));

        // First two should succeed.
        await handler(Request('GET', Uri.parse('http://localhost/test')));
        await handler(Request('GET', Uri.parse('http://localhost/test')));

        // Third should be rate-limited.
        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(429));
      });
    });

    group('logging', () {
      test('passes through and returns the response', () async {
        final handler = const Pipeline()
            .addMiddleware(Middleware.logging())
            .addHandler((_) => Response.ok('hello'));

        final response = await handler(
          Request('GET', Uri.parse('http://localhost/test')),
        );
        expect(response.statusCode, equals(200));
        expect(await response.readAsString(), equals('hello'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Integration: full pipeline
  // ---------------------------------------------------------------------------
  group('Full pipeline integration', () {
    late InMemoryStorage storage;
    late Handler handler;

    setUp(() {
      storage = InMemoryStorage();
      final routes = Routes(storage);
      handler = const Pipeline()
          .addMiddleware(Middleware.errorHandler())
          .addMiddleware(Middleware.logging())
          .addMiddleware(Middleware.cors())
          .addHandler(routes.router.call);
    });

    test(
      'register -> upload prekey -> fetch prekey -> send message -> fetch messages',
      () async {
        // 1. Register Alice.
        final regResponse = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/register'),
            body: jsonEncode({
              'userId': 'alice',
              'publicKey': base64Encode([1, 2, 3]),
            }),
          ),
        );
        expect(regResponse.statusCode, equals(201));

        // 2. Alice uploads a pre-key bundle.
        final pkUploadResponse = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/prekeys'),
            body: jsonEncode({
              'userId': 'alice',
              'bundle': base64Encode([10, 20, 30]),
            }),
          ),
        );
        expect(pkUploadResponse.statusCode, equals(200));

        // 3. Bob fetches Alice's pre-key bundle.
        final pkFetchResponse = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/prekeys/alice')),
        );
        expect(pkFetchResponse.statusCode, equals(200));
        final pkBody =
            jsonDecode(await pkFetchResponse.readAsString())
                as Map<String, dynamic>;
        expect(base64Decode(pkBody['bundle'] as String), equals([10, 20, 30]));

        // Pre-key should be consumed (one-time use).
        final pkGoneResponse = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/prekeys/alice')),
        );
        expect(pkGoneResponse.statusCode, equals(404));

        // 4. Bob sends a key exchange message to Alice.
        final msgSendResponse = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/messages/alice'),
            body: jsonEncode({
              'senderId': 'bob',
              'message': base64Encode([50, 60, 70]),
            }),
          ),
        );
        expect(msgSendResponse.statusCode, equals(200));

        // 5. Alice fetches her pending messages.
        final msgFetchResponse = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/messages/alice')),
        );
        expect(msgFetchResponse.statusCode, equals(200));
        final msgBody =
            jsonDecode(await msgFetchResponse.readAsString())
                as Map<String, dynamic>;
        final messages = msgBody['messages'] as List<dynamic>;
        expect(messages, hasLength(1));
        expect(messages[0]['senderId'], equals('bob'));
        expect(
          base64Decode(messages[0]['message'] as String),
          equals([50, 60, 70]),
        );

        // Messages should be cleared after fetch.
        final msgGoneResponse = await handler(
          Request('GET', Uri.parse('http://localhost/api/v1/messages/alice')),
        );
        final goneBody =
            jsonDecode(await msgGoneResponse.readAsString())
                as Map<String, dynamic>;
        expect(goneBody['messages'] as List<dynamic>, isEmpty);
      },
    );
  });
}
