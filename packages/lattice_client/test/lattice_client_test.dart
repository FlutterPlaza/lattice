import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lattice_client/lattice_client.dart';
import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/lattice_protocol.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock HTTP client
// ---------------------------------------------------------------------------

/// A simple mock [http.BaseClient] that records requests and returns
/// responses via a configurable [handler].
class MockHttpClient extends http.BaseClient {
  MockHttpClient(this.handler);

  /// All requests sent through this client, in order.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// A function that produces a response for each request.
  http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

http.Response _jsonResponse(int statusCode, Object body) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: {'content-type': 'application/json'},
);

http.Response _ok([Object? body]) =>
    _jsonResponse(200, body ?? {'status': 'ok'});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // InMemorySecureStorage
  // =========================================================================
  group('InMemorySecureStorage', () {
    late InMemorySecureStorage storage;

    setUp(() {
      storage = InMemorySecureStorage();
    });

    test('saveIdentity and retrieve keys', () async {
      final pk = LongTermPublicKey(
        encapsulationKey: Uint8List.fromList([1, 2, 3]),
        verificationKey: Uint8List.fromList([4, 5, 6]),
      );
      final sk = LongTermSecretKey(
        decapsulationKey: Uint8List.fromList([7, 8, 9]),
        signingKey: Uint8List.fromList([10, 11, 12]),
      );

      await storage.saveIdentity('alice', pk, sk);

      final retrievedPk = await storage.getPublicKey('alice');
      final retrievedSk = await storage.getSecretKey('alice');

      expect(retrievedPk, isNotNull);
      expect(retrievedPk!.encapsulationKey, equals([1, 2, 3]));
      expect(retrievedPk.verificationKey, equals([4, 5, 6]));
      expect(retrievedSk, isNotNull);
      expect(retrievedSk!.decapsulationKey, equals([7, 8, 9]));
      expect(retrievedSk.signingKey, equals([10, 11, 12]));
    });

    test('returns null for unknown user', () async {
      expect(await storage.getPublicKey('nobody'), isNull);
      expect(await storage.getSecretKey('nobody'), isNull);
      expect(await storage.getPreKey('nobody'), isNull);
    });

    test('savePreKey and retrieve', () async {
      final preKey = EphemeralPreKey(
        ephemeralPublicKey: Uint8List.fromList([1]),
        ephemeralSecretKey: Uint8List.fromList([2]),
        signature: Uint8List.fromList([3]),
      );
      await storage.savePreKey('alice', preKey);

      final retrieved = await storage.getPreKey('alice');
      expect(retrieved, isNotNull);
      expect(retrieved!.ephemeralPublicKey, equals([1]));
    });

    test('removePreKey', () async {
      final preKey = EphemeralPreKey(
        ephemeralPublicKey: Uint8List.fromList([1]),
        ephemeralSecretKey: Uint8List.fromList([2]),
        signature: Uint8List.fromList([3]),
      );
      await storage.savePreKey('alice', preKey);
      await storage.removePreKey('alice');

      expect(await storage.getPreKey('alice'), isNull);
    });

    test('clear removes all data', () async {
      final pk = LongTermPublicKey(
        encapsulationKey: Uint8List.fromList([1]),
        verificationKey: Uint8List.fromList([2]),
      );
      final sk = LongTermSecretKey(
        decapsulationKey: Uint8List.fromList([3]),
        signingKey: Uint8List.fromList([4]),
      );
      final preKey = EphemeralPreKey(
        ephemeralPublicKey: Uint8List.fromList([5]),
        ephemeralSecretKey: Uint8List.fromList([6]),
        signature: Uint8List.fromList([7]),
      );
      await storage.saveIdentity('alice', pk, sk);
      await storage.savePreKey('alice', preKey);

      await storage.clear();

      expect(await storage.getPublicKey('alice'), isNull);
      expect(await storage.getSecretKey('alice'), isNull);
      expect(await storage.getPreKey('alice'), isNull);
    });
  });

  // =========================================================================
  // SessionManager
  // =========================================================================
  group('SessionManager', () {
    late SessionManager manager;

    Session makeSession(String peer) => Session(
      sessionId: SessionId(Uint8List.fromList([1, 2, 3])),
      sessionKey: Uint8List.fromList([4, 5, 6]),
      localIdentity: 'me',
      remoteIdentity: peer,
    );

    setUp(() {
      manager = SessionManager();
    });

    test('initially has no sessions', () {
      expect(manager.sessionCount, equals(0));
      expect(manager.activeSessions, isEmpty);
      expect(manager.hasSession('alice'), isFalse);
    });

    test('addSession and getSession', () {
      final session = makeSession('alice');
      manager.addSession('alice', session);

      expect(manager.hasSession('alice'), isTrue);
      expect(manager.sessionCount, equals(1));
      expect(manager.getSession('alice'), same(session));
    });

    test('getSession returns null for unknown peer', () {
      expect(manager.getSession('unknown'), isNull);
    });

    test('activeSessions lists all sessions', () {
      manager.addSession('alice', makeSession('alice'));
      manager.addSession('bob', makeSession('bob'));

      final active = manager.activeSessions;
      expect(active, hasLength(2));
    });

    test('removeSession', () {
      manager.addSession('alice', makeSession('alice'));
      manager.removeSession('alice');

      expect(manager.hasSession('alice'), isFalse);
      expect(manager.sessionCount, equals(0));
    });

    test('addSession replaces existing session for same peer', () {
      final session1 = makeSession('alice');
      final session2 = makeSession('alice');
      manager.addSession('alice', session1);
      manager.addSession('alice', session2);

      expect(manager.sessionCount, equals(1));
      expect(manager.getSession('alice'), same(session2));
    });
  });

  // =========================================================================
  // Connection
  // =========================================================================
  group('Connection', () {
    test('register sends correct POST request', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockHttpClient((request) {
        capturedRequest = request;
        return _jsonResponse(201, {'status': 'registered', 'userId': 'alice'});
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final keyData = Uint8List.fromList([1, 2, 3, 4]);
      await conn.register('alice', keyData);

      expect(capturedRequest.url.path, equals('/api/v1/register'));
      expect(capturedRequest.method, equals('POST'));

      final body =
          jsonDecode((capturedRequest as http.Request).body)
              as Map<String, dynamic>;
      expect(body['userId'], equals('alice'));
      expect(body['publicKey'], equals(base64Encode([1, 2, 3, 4])));

      conn.close();
    });

    test('uploadPreKey sends correct POST request', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockHttpClient((request) {
        capturedRequest = request;
        return _jsonResponse(200, {'status': 'stored', 'userId': 'alice'});
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final bundleData = Uint8List.fromList([10, 20, 30]);
      await conn.uploadPreKey('alice', bundleData);

      expect(capturedRequest.url.path, equals('/api/v1/prekeys'));
      final body =
          jsonDecode((capturedRequest as http.Request).body)
              as Map<String, dynamic>;
      expect(body['userId'], equals('alice'));
      expect(body['bundle'], equals(base64Encode([10, 20, 30])));

      conn.close();
    });

    test('fetchPreKey returns data on 200', () async {
      final bundleBytes = Uint8List.fromList([7, 8, 9]);
      final mockClient = MockHttpClient((request) {
        return _jsonResponse(200, {
          'userId': 'alice',
          'bundle': base64Encode(bundleBytes),
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final result = await conn.fetchPreKey('alice');
      expect(result, isNotNull);
      expect(result, equals([7, 8, 9]));

      conn.close();
    });

    test('fetchPreKey returns null on 404', () async {
      final mockClient = MockHttpClient((request) {
        return _jsonResponse(404, {
          'error': 'No pre-key bundle for user "alice"',
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final result = await conn.fetchPreKey('alice');
      expect(result, isNull);

      conn.close();
    });

    test('sendMessage sends correct POST request', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockHttpClient((request) {
        capturedRequest = request;
        return _jsonResponse(200, {'status': 'delivered'});
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final messageData = Uint8List.fromList([11, 22, 33]);
      await conn.sendMessage('bob', 'alice', messageData);

      expect(capturedRequest.url.path, equals('/api/v1/messages/bob'));
      final body =
          jsonDecode((capturedRequest as http.Request).body)
              as Map<String, dynamic>;
      expect(body['senderId'], equals('alice'));
      expect(body['message'], equals(base64Encode([11, 22, 33])));

      conn.close();
    });

    test('fetchMessages returns parsed list', () async {
      final msg1Data = Uint8List.fromList([1, 2]);
      final msg2Data = Uint8List.fromList([3, 4]);
      final mockClient = MockHttpClient((request) {
        return _jsonResponse(200, {
          'messages': [
            {
              'senderId': 'bob',
              'message': base64Encode(msg1Data),
              'sentAt': '2025-01-01T00:00:00.000Z',
            },
            {
              'senderId': 'carol',
              'message': base64Encode(msg2Data),
              'sentAt': '2025-01-02T00:00:00.000Z',
            },
          ],
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final messages = await conn.fetchMessages('alice');
      expect(messages, hasLength(2));
      expect(messages[0].senderId, equals('bob'));
      expect(messages[0].messageData, equals([1, 2]));
      expect(messages[1].senderId, equals('carol'));
      expect(messages[1].messageData, equals([3, 4]));

      conn.close();
    });

    test('health returns parsed map', () async {
      final mockClient = MockHttpClient((request) {
        return _jsonResponse(200, {
          'status': 'ok',
          'uptime': 42,
          'version': '0.1.0',
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final result = await conn.health();
      expect(result['status'], equals('ok'));
      expect(result['uptime'], equals(42));

      conn.close();
    });

    test('throws LatticeApiException on server error', () async {
      final mockClient = MockHttpClient((request) {
        return _jsonResponse(500, {'error': 'Internal server error'});
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      expect(
        () => conn.register('alice', Uint8List.fromList([1])),
        throwsA(isA<LatticeApiException>()),
      );

      conn.close();
    });

    test('setAuthToken includes Bearer header', () async {
      late http.BaseRequest capturedRequest;
      final mockClient = MockHttpClient((request) {
        capturedRequest = request;
        return _jsonResponse(200, {
          'status': 'ok',
          'uptime': 0,
          'version': '0.1.0',
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      conn.setAuthToken('my-token');

      await conn.health();

      expect(
        capturedRequest.headers['authorization'],
        equals('Bearer my-token'),
      );

      conn.close();
    });
  });

  // =========================================================================
  // LatticeClient
  // =========================================================================
  group('LatticeClient', () {
    test('register generates keys and calls server', () async {
      final requests = <http.BaseRequest>[];
      final mockClient = MockHttpClient((request) {
        requests.add(request);
        if (request.url.path == '/api/v1/register') {
          return _jsonResponse(201, {
            'status': 'registered',
            'userId': 'alice',
          });
        }
        return _ok();
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final storage = InMemorySecureStorage();
      final client = LatticeClient(
        userId: 'alice',
        connection: conn,
        storage: storage,
      );

      await client.register();

      // Verify a registration request was sent.
      expect(requests, hasLength(1));
      expect(requests.first.url.path, equals('/api/v1/register'));

      // Verify keys were stored locally.
      final pk = await storage.getPublicKey('alice');
      final sk = await storage.getSecretKey('alice');
      expect(pk, isNotNull);
      expect(sk, isNotNull);

      client.close();
    });

    test('uploadPreKey requires prior registration', () async {
      final mockClient = MockHttpClient((request) => _ok());
      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final client = LatticeClient(userId: 'alice', connection: conn);

      expect(client.uploadPreKey, throwsStateError);

      client.close();
    });

    test('uploadPreKey generates and uploads bundle', () async {
      final requests = <http.BaseRequest>[];
      final mockClient = MockHttpClient((request) {
        requests.add(request);
        if (request.url.path == '/api/v1/register') {
          return _jsonResponse(201, {
            'status': 'registered',
            'userId': 'alice',
          });
        }
        if (request.url.path == '/api/v1/prekeys') {
          return _jsonResponse(200, {'status': 'stored', 'userId': 'alice'});
        }
        return _ok();
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final storage = InMemorySecureStorage();
      final client = LatticeClient(
        userId: 'alice',
        connection: conn,
        storage: storage,
      );

      await client.register();
      await client.uploadPreKey();

      // Expect register + uploadPreKey requests.
      expect(requests, hasLength(2));
      expect(requests[1].url.path, equals('/api/v1/prekeys'));

      // Verify pre-key was stored locally.
      final preKey = await storage.getPreKey('alice');
      expect(preKey, isNotNull);

      client.close();
    });

    test('initiateSession throws when not registered', () async {
      final mockClient = MockHttpClient((request) {
        // Return a valid pre-key bundle so the fetch succeeds.
        final crypto = const CryptoProvider();
        final reg = Registration(crypto);
        final result = reg.generate();
        final initiator = Initiator(crypto);
        final upload = initiator.uploadPreKey(
          lpkA: result.publicKey,
          lskA: result.secretKey,
        );
        return _jsonResponse(200, {
          'userId': 'bob',
          'bundle': base64Encode(upload.bundle.serialize()),
        });
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final client = LatticeClient(userId: 'alice', connection: conn);

      expect(() => client.initiateSession('bob'), throwsStateError);

      client.close();
    });

    test('initiateSession throws when peer has no pre-key', () async {
      final mockClient = MockHttpClient((request) {
        if (request.url.path == '/api/v1/register') {
          return _jsonResponse(201, {
            'status': 'registered',
            'userId': 'alice',
          });
        }
        if (request.url.path.startsWith('/api/v1/prekeys/')) {
          return _jsonResponse(404, {
            'error': 'No pre-key bundle for user "bob"',
          });
        }
        return _ok();
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final client = LatticeClient(userId: 'alice', connection: conn);
      await client.register();

      expect(() => client.initiateSession('bob'), throwsStateError);

      client.close();
    });

    test('full handshake: initiateSession + respondToSessions', () async {
      // Set up two clients (Alice and Bob) that talk to each other through
      // an in-memory "server" backed by simple maps.
      final crypto = const CryptoProvider();

      // Shared "server" state.
      final preKeyStore = <String, Uint8List>{};
      final messageStore = <String, List<Map<String, dynamic>>>{};
      final registeredUsers = <String, Uint8List>{};

      http.Response handleRequest(http.BaseRequest request) {
        final path = request.url.path;
        final body =
            (request is http.Request && request.method == 'POST')
                ? jsonDecode(request.body) as Map<String, dynamic>?
                : null;

        // POST /api/v1/register
        if (path == '/api/v1/register' && request.method == 'POST') {
          final userId = body!['userId'] as String;
          registeredUsers[userId] = base64Decode(body['publicKey'] as String);
          return _jsonResponse(201, {'status': 'registered', 'userId': userId});
        }

        // POST /api/v1/prekeys
        if (path == '/api/v1/prekeys' && request.method == 'POST') {
          final userId = body!['userId'] as String;
          preKeyStore[userId] = base64Decode(body['bundle'] as String);
          return _jsonResponse(200, {'status': 'stored', 'userId': userId});
        }

        // GET /api/v1/prekeys/:userId
        if (path.startsWith('/api/v1/prekeys/') && request.method == 'GET') {
          final userId = path.split('/').last;
          final bundle = preKeyStore.remove(userId);
          if (bundle == null) {
            return _jsonResponse(404, {
              'error': 'No pre-key bundle for user "$userId"',
            });
          }
          return _jsonResponse(200, {
            'userId': userId,
            'bundle': base64Encode(bundle),
          });
        }

        // POST /api/v1/messages/:userId
        if (path.startsWith('/api/v1/messages/') && request.method == 'POST') {
          final userId = path.split('/').last;
          messageStore.putIfAbsent(userId, () => <Map<String, dynamic>>[]);
          messageStore[userId]!.add({
            'senderId': body!['senderId'],
            'message': body['message'],
            'sentAt': DateTime.now().toIso8601String(),
          });
          return _jsonResponse(200, {'status': 'delivered'});
        }

        // GET /api/v1/messages/:userId
        if (path.startsWith('/api/v1/messages/') && request.method == 'GET') {
          final userId = path.split('/').last;
          final messages =
              messageStore.remove(userId) ?? <Map<String, dynamic>>[];
          return _jsonResponse(200, {'messages': messages});
        }

        return _jsonResponse(404, {'error': 'Not found'});
      }

      // Create two mock HTTP clients that share the same handler.
      final aliceHttp = MockHttpClient(handleRequest);
      final bobHttp = MockHttpClient(handleRequest);

      final aliceConn = Connection(
        baseUrl: 'http://localhost:8080',
        client: aliceHttp,
      );
      final bobConn = Connection(
        baseUrl: 'http://localhost:8080',
        client: bobHttp,
      );

      final alice = LatticeClient(
        userId: 'alice',
        connection: aliceConn,
        crypto: crypto,
      );
      final bob = LatticeClient(
        userId: 'bob',
        connection: bobConn,
        crypto: crypto,
      );

      // 1. Both register.
      await alice.register();
      await bob.register();

      // 2. Alice uploads a pre-key.
      await alice.uploadPreKey();

      // 3. Bob initiates a session with Alice (Bob = responder).
      final bobSession = await bob.initiateSession('alice');
      expect(bobSession.localIdentity, equals('bob'));
      expect(bobSession.remoteIdentity, equals('alice'));
      expect(bob.sessions.hasSession('alice'), isTrue);

      // 4. Alice responds and finalizes the session (Alice = initiator).
      final aliceSessions = await alice.respondToSessions();
      expect(aliceSessions, hasLength(1));

      final aliceSession = aliceSessions.first;
      expect(aliceSession.localIdentity, equals('alice'));
      expect(aliceSession.remoteIdentity, equals('bob'));
      expect(alice.sessions.hasSession('bob'), isTrue);

      // 5. Both parties derived the same session key.
      expect(aliceSession.sessionKey, equals(bobSession.sessionKey));

      alice.close();
      bob.close();
    });

    test('respondToSessions throws when not registered', () async {
      final mockClient = MockHttpClient((request) => _ok());
      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final client = LatticeClient(userId: 'alice', connection: conn);

      expect(client.respondToSessions, throwsStateError);

      client.close();
    });

    test('respondToSessions throws when no pre-key', () async {
      final mockClient = MockHttpClient((request) {
        if (request.url.path == '/api/v1/register') {
          return _jsonResponse(201, {
            'status': 'registered',
            'userId': 'alice',
          });
        }
        return _ok();
      });

      final conn = Connection(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );
      final client = LatticeClient(userId: 'alice', connection: conn);
      await client.register();

      expect(client.respondToSessions, throwsStateError);

      client.close();
    });
  });

  // =========================================================================
  // LatticeApiException
  // =========================================================================
  group('LatticeApiException', () {
    test('toString contains status code and message', () {
      const ex = LatticeApiException(400, 'Bad request');
      expect(ex.toString(), contains('400'));
      expect(ex.toString(), contains('Bad request'));
    });

    test('statusCode and message are accessible', () {
      const ex = LatticeApiException(500, 'Internal server error');
      expect(ex.statusCode, equals(500));
      expect(ex.message, equals('Internal server error'));
    });
  });
}
