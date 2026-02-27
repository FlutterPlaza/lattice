import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_deploy/lattice_deploy.dart';
import 'package:lattice_monitor/lattice_monitor.dart';
import 'package:lattice_protocol/lattice_protocol.dart';
import 'package:lattice_server/lattice_server.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Fixed 32-byte seed for key derivation (Ext + PRF).
final Uint8List _seed = Uint8List.fromList(
  List<int>.generate(32, (i) => i + 1),
);

/// Runs the full SC-AKE handshake between Alice and Bob and returns both
/// session results.
({InitiatorSessionResult alice, ResponderSessionResult bob}) _handshake(
  CryptoProvider crypto,
) {
  // 1. Registration
  final reg = Registration(crypto);
  final aliceReg = reg.generate();
  final bobReg = reg.generate();

  // 2. Alice uploads a pre-key
  final initiator = Initiator(crypto);
  final preKeyResult = initiator.uploadPreKey(
    lpkA: aliceReg.publicKey,
    lskA: aliceReg.secretKey,
  );

  // 3. Bob creates a session using Alice's pre-key bundle
  final responder = Responder(crypto);
  final bobSession = responder.createSession(
    identityA: 'alice',
    identityB: 'bob',
    bundleA: preKeyResult.bundle,
    lpkB: bobReg.publicKey,
    lskB: bobReg.secretKey,
    seed: _seed,
  );

  // 4. Alice finalizes the session using Bob's key-exchange message
  final aliceSession = initiator.finalizeSession(
    identityA: 'alice',
    identityB: 'bob',
    lpkA: aliceReg.publicKey,
    lpkB: bobReg.publicKey,
    lskA: aliceReg.secretKey,
    preKey: preKeyResult.preKey,
    message: bobSession.message,
    seed: _seed,
  );

  return (alice: aliceSession, bob: bobSession);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ==========================================================================
  // 1. Full SC-AKE handshake at all three security levels
  // ==========================================================================

  group('SC-AKE handshake', () {
    for (final level in SecurityLevel.values) {
      test('completes at ${level.name} (${level.bits}-bit)', () {
        final crypto = CryptoProvider(level: level);
        final result = _handshake(crypto);

        // Session keys must match.
        expect(result.alice.sessionKey, equals(result.bob.sessionKey));

        // Session IDs must match.
        expect(result.alice.sessionId.data, equals(result.bob.sessionId.data));

        // Session key must have the expected length.
        expect(result.alice.sessionKey.length, equals(level.sessionKeySize));
      });
    }
  });

  // ==========================================================================
  // 2. Tampered message detection
  // ==========================================================================

  group('tampered message detection', () {
    test('detects tampered ciphertext', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final bobReg = reg.generate();

      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      final responder = const Responder(crypto);
      final bobSession = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: preKeyResult.bundle,
        lpkB: bobReg.publicKey,
        lskB: bobReg.secretKey,
        seed: _seed,
      );

      // Tamper with the ciphertext (flip a byte).
      final tamperedCiphertext = Uint8List.fromList(
        bobSession.message.ciphertext,
      );
      tamperedCiphertext[0] ^= 0xFF;

      final tamperedMessage = KeyExchangeMessage(
        ciphertext: tamperedCiphertext,
        ephemeralCiphertext: bobSession.message.ephemeralCiphertext,
        encryptedSignature: bobSession.message.encryptedSignature,
      );

      expect(
        () => initiator.finalizeSession(
          identityA: 'alice',
          identityB: 'bob',
          lpkA: aliceReg.publicKey,
          lpkB: bobReg.publicKey,
          lskA: aliceReg.secretKey,
          preKey: preKeyResult.preKey,
          message: tamperedMessage,
          seed: _seed,
        ),
        throwsStateError,
      );
    });

    test('detects tampered ephemeral ciphertext', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final bobReg = reg.generate();

      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      final responder = const Responder(crypto);
      final bobSession = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: preKeyResult.bundle,
        lpkB: bobReg.publicKey,
        lskB: bobReg.secretKey,
        seed: _seed,
      );

      // Tamper with the ephemeral ciphertext.
      final tamperedEphCt = Uint8List.fromList(
        bobSession.message.ephemeralCiphertext,
      );
      tamperedEphCt[0] ^= 0xFF;

      final tamperedMessage = KeyExchangeMessage(
        ciphertext: bobSession.message.ciphertext,
        ephemeralCiphertext: tamperedEphCt,
        encryptedSignature: bobSession.message.encryptedSignature,
      );

      expect(
        () => initiator.finalizeSession(
          identityA: 'alice',
          identityB: 'bob',
          lpkA: aliceReg.publicKey,
          lpkB: bobReg.publicKey,
          lskA: aliceReg.secretKey,
          preKey: preKeyResult.preKey,
          message: tamperedMessage,
          seed: _seed,
        ),
        throwsStateError,
      );
    });

    test('detects tampered encrypted signature', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final bobReg = reg.generate();

      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      final responder = const Responder(crypto);
      final bobSession = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: preKeyResult.bundle,
        lpkB: bobReg.publicKey,
        lskB: bobReg.secretKey,
        seed: _seed,
      );

      // Tamper with the encrypted signature.
      final tamperedSig = Uint8List.fromList(
        bobSession.message.encryptedSignature,
      );
      tamperedSig[0] ^= 0xFF;

      final tamperedMessage = KeyExchangeMessage(
        ciphertext: bobSession.message.ciphertext,
        ephemeralCiphertext: bobSession.message.ephemeralCiphertext,
        encryptedSignature: tamperedSig,
      );

      expect(
        () => initiator.finalizeSession(
          identityA: 'alice',
          identityB: 'bob',
          lpkA: aliceReg.publicKey,
          lpkB: bobReg.publicKey,
          lskA: aliceReg.secretKey,
          preKey: preKeyResult.preKey,
          message: tamperedMessage,
          seed: _seed,
        ),
        throwsStateError,
      );
    });

    test('rejects invalid pre-key signature', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final bobReg = reg.generate();

      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      // Tamper with the pre-key signature.
      final tamperedSig = Uint8List.fromList(preKeyResult.bundle.signature);
      tamperedSig[0] ^= 0xFF;

      final tamperedBundle = PreKeyBundle(
        longTermPublicKey: preKeyResult.bundle.longTermPublicKey,
        ephemeralPublicKey: preKeyResult.bundle.ephemeralPublicKey,
        signature: tamperedSig,
      );

      final responder = const Responder(crypto);
      expect(
        () => responder.createSession(
          identityA: 'alice',
          identityB: 'bob',
          bundleA: tamperedBundle,
          lpkB: bobReg.publicKey,
          lskB: bobReg.secretKey,
          seed: _seed,
        ),
        throwsStateError,
      );
    });
  });

  // ==========================================================================
  // 3. Concurrent sessions between multiple user pairs
  // ==========================================================================

  group('concurrent sessions', () {
    test('multiple independent sessions produce unique keys', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);

      // Create 4 users.
      final users = List.generate(4, (_) => reg.generate());
      final names = ['alice', 'bob', 'carol', 'dave'];

      // Establish sessions for (0,1), (0,2), (1,3), (2,3).
      final pairs = [(0, 1), (0, 2), (1, 3), (2, 3)];

      final sessionKeys = <List<int>>[];

      for (final (a, b) in pairs) {
        final initiator = const Initiator(crypto);
        final preKeyResult = initiator.uploadPreKey(
          lpkA: users[a].publicKey,
          lskA: users[a].secretKey,
        );

        final responder = const Responder(crypto);
        final bobResult = responder.createSession(
          identityA: names[a],
          identityB: names[b],
          bundleA: preKeyResult.bundle,
          lpkB: users[b].publicKey,
          lskB: users[b].secretKey,
          seed: _seed,
        );

        final aliceResult = initiator.finalizeSession(
          identityA: names[a],
          identityB: names[b],
          lpkA: users[a].publicKey,
          lpkB: users[b].publicKey,
          lskA: users[a].secretKey,
          preKey: preKeyResult.preKey,
          message: bobResult.message,
          seed: _seed,
        );

        // Both sides agree.
        expect(aliceResult.sessionKey, equals(bobResult.sessionKey));
        sessionKeys.add(aliceResult.sessionKey.toList());
      }

      // All session keys should be unique.
      for (var i = 0; i < sessionKeys.length; i++) {
        for (var j = i + 1; j < sessionKeys.length; j++) {
          expect(
            sessionKeys[i],
            isNot(equals(sessionKeys[j])),
            reason: 'Session keys for pairs $i and $j must differ',
          );
        }
      }
    });
  });

  // ==========================================================================
  // 4. Serialization round-trips
  // ==========================================================================

  group('serialization round-trips', () {
    test('LongTermPublicKey serialize/deserialize', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final result = reg.generate();

      final serialized = result.publicKey.serialize();
      final deserialized = LongTermPublicKey.deserialize(serialized);

      expect(
        deserialized.encapsulationKey,
        equals(result.publicKey.encapsulationKey),
      );
      expect(
        deserialized.verificationKey,
        equals(result.publicKey.verificationKey),
      );
    });

    test('PreKeyBundle serialize/deserialize', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      final serialized = preKeyResult.bundle.serialize();
      final deserialized = PreKeyBundle.deserialize(serialized);

      expect(
        deserialized.longTermPublicKey.encapsulationKey,
        equals(preKeyResult.bundle.longTermPublicKey.encapsulationKey),
      );
      expect(
        deserialized.longTermPublicKey.verificationKey,
        equals(preKeyResult.bundle.longTermPublicKey.verificationKey),
      );
      expect(
        deserialized.ephemeralPublicKey,
        equals(preKeyResult.bundle.ephemeralPublicKey),
      );
      expect(deserialized.signature, equals(preKeyResult.bundle.signature));
    });

    test('KeyExchangeMessage serialize/deserialize', () {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final result = _handshake(crypto);

      final serialized = result.bob.message.serialize();
      final deserialized = KeyExchangeMessage.deserialize(serialized);

      expect(deserialized.ciphertext, equals(result.bob.message.ciphertext));
      expect(
        deserialized.ephemeralCiphertext,
        equals(result.bob.message.ephemeralCiphertext),
      );
      expect(
        deserialized.encryptedSignature,
        equals(result.bob.message.encryptedSignature),
      );
    });

    test('Serialization length-prefixed string round-trip', () {
      final builder = BytesBuilder(copy: false);
      Serialization.writeLengthPrefixedString(builder, 'hello');
      Serialization.writeLengthPrefixedString(builder, 'world');
      final data = builder.takeBytes();

      var offset = 0;
      final (s1, c1) = Serialization.readLengthPrefixedString(data, offset);
      offset += c1;
      final (s2, _) = Serialization.readLengthPrefixedString(data, offset);

      expect(s1, equals('hello'));
      expect(s2, equals('world'));
    });

    test('Serialization length-prefixed bytes round-trip', () {
      final builder = BytesBuilder(copy: false);
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      Serialization.writeLengthPrefixed(builder, payload);
      final data = builder.takeBytes();

      final (recovered, consumed) = Serialization.readLengthPrefixed(data, 0);
      expect(recovered, equals(payload));
      expect(consumed, equals(4 + 5)); // 4-byte prefix + 5-byte payload
    });
  });

  // ==========================================================================
  // 5. Server storage operations
  // ==========================================================================

  group('server storage operations', () {
    late InMemoryStorage storage;

    setUp(() {
      storage = InMemoryStorage();
    });

    test('register and retrieve users', () async {
      final record = UserRecord(
        userId: 'alice',
        publicKeyData: Uint8List.fromList([1, 2, 3]),
      );
      await storage.registerUser(record);

      final retrieved = await storage.getUser('alice');
      expect(retrieved, isNotNull);
      expect(retrieved!.userId, equals('alice'));
      expect(retrieved.publicKeyData, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('duplicate registration throws', () async {
      final record = UserRecord(
        userId: 'alice',
        publicKeyData: Uint8List.fromList([1, 2, 3]),
      );
      await storage.registerUser(record);
      expect(() => storage.registerUser(record), throwsStateError);
    });

    test('store and retrieve pre-key bundles', () async {
      final record = PreKeyRecord(
        userId: 'alice',
        bundleData: Uint8List.fromList([10, 20, 30]),
      );
      await storage.storePreKey(record);

      final retrieved = await storage.getPreKey('alice');
      expect(retrieved, isNotNull);
      expect(retrieved!.bundleData, equals(Uint8List.fromList([10, 20, 30])));

      await storage.removePreKey('alice');
      final removed = await storage.getPreKey('alice');
      expect(removed, isNull);
    });

    test('store and retrieve messages', () async {
      final msg1 = MessageRecord(
        recipientId: 'alice',
        senderId: 'bob',
        messageData: Uint8List.fromList([1]),
      );
      final msg2 = MessageRecord(
        recipientId: 'alice',
        senderId: 'carol',
        messageData: Uint8List.fromList([2]),
      );
      await storage.storeMessage(msg1);
      await storage.storeMessage(msg2);

      final messages = await storage.getMessages('alice');
      expect(messages.length, equals(2));
      expect(messages[0].senderId, equals('bob'));
      expect(messages[1].senderId, equals('carol'));

      await storage.clearMessages('alice');
      final cleared = await storage.getMessages('alice');
      expect(cleared, isEmpty);
    });

    test('stats are accurate', () async {
      await storage.registerUser(
        UserRecord(userId: 'a', publicKeyData: Uint8List(0)),
      );
      await storage.registerUser(
        UserRecord(userId: 'b', publicKeyData: Uint8List(0)),
      );
      await storage.storePreKey(
        PreKeyRecord(userId: 'a', bundleData: Uint8List(0)),
      );
      await storage.storeMessage(
        MessageRecord(
          recipientId: 'a',
          senderId: 'b',
          messageData: Uint8List(0),
        ),
      );
      await storage.storeMessage(
        MessageRecord(
          recipientId: 'b',
          senderId: 'a',
          messageData: Uint8List(0),
        ),
      );

      expect(await storage.getUserCount(), equals(2));
      expect(await storage.getPreKeyCount(), equals(1));
      expect(await storage.getMessageCount(), equals(2));
    });

    test('UserRecord JSON round-trip', () {
      final record = UserRecord(
        userId: 'alice',
        publicKeyData: Uint8List.fromList([1, 2, 3]),
      );
      final json = record.toJson();
      final restored = UserRecord.fromJson(json);
      expect(restored.userId, equals('alice'));
      expect(restored.publicKeyData, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('PreKeyRecord JSON round-trip', () {
      final record = PreKeyRecord(
        userId: 'bob',
        bundleData: Uint8List.fromList([4, 5, 6]),
      );
      final json = record.toJson();
      final restored = PreKeyRecord.fromJson(json);
      expect(restored.userId, equals('bob'));
      expect(restored.bundleData, equals(Uint8List.fromList([4, 5, 6])));
    });

    test('MessageRecord JSON round-trip', () {
      final record = MessageRecord(
        recipientId: 'alice',
        senderId: 'bob',
        messageData: Uint8List.fromList([7, 8, 9]),
      );
      final json = record.toJson();
      final restored = MessageRecord.fromJson(json);
      expect(restored.recipientId, equals('alice'));
      expect(restored.senderId, equals('bob'));
      expect(restored.messageData, equals(Uint8List.fromList([7, 8, 9])));
    });
  });

  // ==========================================================================
  // 6. End-to-end flow with server storage
  // ==========================================================================

  group('end-to-end with server storage', () {
    test('full protocol flow through InMemoryStorage', () async {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);

      // Register Alice and Bob.
      final aliceReg = reg.generate();
      final bobReg = reg.generate();

      final serverStorage = InMemoryStorage();

      // Store registrations.
      await serverStorage.registerUser(
        UserRecord(
          userId: 'alice',
          publicKeyData: aliceReg.publicKey.serialize(),
        ),
      );
      await serverStorage.registerUser(
        UserRecord(userId: 'bob', publicKeyData: bobReg.publicKey.serialize()),
      );

      // Alice uploads a pre-key.
      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      await serverStorage.storePreKey(
        PreKeyRecord(
          userId: 'alice',
          bundleData: preKeyResult.bundle.serialize(),
        ),
      );

      // Bob fetches Alice's pre-key bundle from storage.
      final bundleRecord = await serverStorage.getPreKey('alice');
      expect(bundleRecord, isNotNull);

      final fetchedBundle = PreKeyBundle.deserialize(bundleRecord!.bundleData);

      // Bob creates a session.
      final responder = const Responder(crypto);
      final bobSession = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: fetchedBundle,
        lpkB: bobReg.publicKey,
        lskB: bobReg.secretKey,
        seed: _seed,
      );

      // Bob sends his key-exchange message through the server.
      await serverStorage.storeMessage(
        MessageRecord(
          recipientId: 'alice',
          senderId: 'bob',
          messageData: bobSession.message.serialize(),
        ),
      );

      // Alice retrieves the message.
      final messages = await serverStorage.getMessages('alice');
      expect(messages.length, equals(1));

      final receivedMessage = KeyExchangeMessage.deserialize(
        messages.first.messageData,
      );

      // Alice finalizes the session.
      final aliceSession = initiator.finalizeSession(
        identityA: 'alice',
        identityB: 'bob',
        lpkA: aliceReg.publicKey,
        lpkB: bobReg.publicKey,
        lskA: aliceReg.secretKey,
        preKey: preKeyResult.preKey,
        message: receivedMessage,
        seed: _seed,
      );

      // Both sides agree on the session key and session ID.
      expect(aliceSession.sessionKey, equals(bobSession.sessionKey));
      expect(aliceSession.sessionId.data, equals(bobSession.sessionId.data));
    });
  });

  // ==========================================================================
  // 7. Monitoring components (HealthChecker with mock HTTP client)
  // ==========================================================================

  group('monitoring components', () {
    test('HealthChecker reports healthy for 200 OK', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'ok', 'uptime': 42, 'version': '0.1.0'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: mockClient,
      );

      final status = await checker.check();
      expect(status.healthy, isTrue);
      expect(status.uptimeSeconds, equals(42));
      expect(status.version, equals('0.1.0'));
      expect(checker.history.length, equals(1));
      expect(checker.consecutiveHealthy, equals(1));
      expect(checker.uptimePercentage, equals(100.0));

      checker.close();
    });

    test('HealthChecker reports unhealthy for non-200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('error', 500);
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: mockClient,
      );

      final status = await checker.check();
      expect(status.healthy, isFalse);
      expect(status.error, equals('HTTP 500'));
      expect(checker.consecutiveHealthy, equals(0));
      expect(checker.uptimePercentage, equals(0.0));

      checker.close();
    });

    test('HealthChecker tracks consecutive failures', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount <= 2) {
          return http.Response('error', 500);
        }
        return http.Response(
          jsonEncode({'status': 'ok', 'uptime': 10, 'version': '0.1.0'}),
          200,
        );
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: mockClient,
      );

      await checker.check(); // fail
      await checker.check(); // fail
      expect(checker.consecutiveHealthy, equals(0));

      await checker.check(); // success
      expect(checker.consecutiveHealthy, equals(1));

      checker.close();
    });

    test('AlertManager triggers alerts correctly', () {
      final alerts = <Alert>[];
      final manager = AlertManager(
        threshold: const AlertThreshold(
          maxConsecutiveFailures: 2,
          maxPendingMessages: 10,
          minUptimePercentage: 99.0,
        ),
        onAlert: alerts.add,
      );

      // Single failure: warning.
      manager.evaluateHealth(
        HealthStatus(
          endpoint: 'http://localhost',
          healthy: false,
          checkedAt: DateTime.now(),
          error: 'timeout',
        ),
        consecutiveFailures: 1,
      );
      expect(alerts.length, equals(1));
      expect(alerts.last.severity, equals(AlertSeverity.warning));

      // Consecutive failures at threshold: critical.
      manager.evaluateHealth(
        HealthStatus(
          endpoint: 'http://localhost',
          healthy: false,
          checkedAt: DateTime.now(),
          error: 'timeout',
        ),
        consecutiveFailures: 2,
      );
      expect(alerts.length, equals(2));
      expect(alerts.last.severity, equals(AlertSeverity.critical));

      // Uptime below threshold: critical.
      manager.evaluateUptime(95.0);
      expect(alerts.length, equals(3));
      expect(alerts.last.severity, equals(AlertSeverity.critical));

      // Clear alerts.
      manager.clearAlerts();
      expect(manager.alerts, isEmpty);
    });

    test('MetricsCollector collects metrics from mock server', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'users': 5,
            'preKeys': 3,
            'pendingMessages': 12,
            'uptime': 600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final collector = MetricsCollector(
        endpoint: 'http://localhost:8080',
        client: mockClient,
      );

      final snapshot = await collector.collect();
      expect(snapshot.userCount, equals(5));
      expect(snapshot.preKeyCount, equals(3));
      expect(snapshot.pendingMessageCount, equals(12));
      expect(snapshot.uptimeSeconds, equals(600));
      expect(collector.history.length, equals(1));

      collector.close();
    });
  });

  // ==========================================================================
  // 8. Deployment config save/load round-trip
  // ==========================================================================

  group('deployment config', () {
    test('save and load round-trip', () async {
      final config = const DeployConfig(
        target: DeployTarget.aws,
        serverHost: '0.0.0.0',
        serverPort: 9090,
        storagePath: '/data/lattice',
        dockerImage: 'my-lattice',
        registryUrl: '123456.dkr.ecr.us-east-1.amazonaws.com',
        scaling: ScalingConfig(
          minInstances: 2,
          maxInstances: 8,
          cpuThresholdPercent: 75,
          memoryThresholdPercent: 85,
        ),
        environment: {'LOG_LEVEL': 'debug', 'TLS': 'true'},
      );

      // Save to a temp file.
      final tempDir = Directory.systemTemp.createTempSync('lattice_test_');
      final configPath = '${tempDir.path}/deploy.yaml';

      try {
        await config.save(path: configPath);

        // Load it back.
        final loaded = DeployConfig.load(path: configPath);
        expect(loaded, isNotNull);
        expect(loaded!.target, equals(DeployTarget.aws));
        expect(loaded.serverPort, equals(9090));
        expect(loaded.storagePath, equals('/data/lattice'));
        expect(loaded.dockerImage, equals('my-lattice'));
        expect(
          loaded.registryUrl,
          equals('123456.dkr.ecr.us-east-1.amazonaws.com'),
        );
        expect(loaded.scaling.minInstances, equals(2));
        expect(loaded.scaling.maxInstances, equals(8));
        expect(loaded.scaling.cpuThresholdPercent, equals(75));
        expect(loaded.scaling.memoryThresholdPercent, equals(85));
        expect(loaded.environment['LOG_LEVEL'], equals('debug'));
        expect(loaded.environment['TLS'], equals('true'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fromMap handles defaults', () {
      final config = DeployConfig.fromMap(<String, dynamic>{});
      expect(config.target, equals(DeployTarget.local));
      expect(config.serverHost, equals('0.0.0.0'));
      expect(config.serverPort, equals(8080));
      expect(config.scaling.minInstances, equals(1));
      expect(config.scaling.maxInstances, equals(3));
    });

    test('toMap round-trip', () {
      final config = const DeployConfig(
        target: DeployTarget.gcp,
        serverPort: 443,
        scaling: ScalingConfig(minInstances: 3, maxInstances: 10),
      );
      final map = config.toMap();
      final restored = DeployConfig.fromMap(map);
      expect(restored.target, equals(DeployTarget.gcp));
      expect(restored.serverPort, equals(443));
      expect(restored.scaling.minInstances, equals(3));
      expect(restored.scaling.maxInstances, equals(10));
    });

    test('load returns null for missing file', () {
      final loaded = DeployConfig.load(
        path: '/tmp/nonexistent_lattice_test_config.yaml',
      );
      expect(loaded, isNull);
    });

    test('parseDeployTarget handles all values', () {
      expect(parseDeployTarget('local'), equals(DeployTarget.local));
      expect(parseDeployTarget('aws'), equals(DeployTarget.aws));
      expect(parseDeployTarget('azure'), equals(DeployTarget.azure));
      expect(parseDeployTarget('gcp'), equals(DeployTarget.gcp));
      expect(parseDeployTarget('unknown'), equals(DeployTarget.local));
    });

    test('Deployer dry-run produces result', () async {
      final config = const DeployConfig(
        target: DeployTarget.local,
        dockerImage: 'test-image',
        environment: {'KEY': 'val'},
      );
      final deployer = Deployer(config);
      final result = await deployer.deploy(dryRun: true);
      expect(result.success, isTrue);
      expect(result.message, contains('Dry-run'));
      expect(result.message, contains('test-image'));
    });
  });

  // ==========================================================================
  // 9. Protocol store abstractions
  // ==========================================================================

  group('protocol store abstractions', () {
    test('InMemoryIdentityStore save and retrieve', () async {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final result = reg.generate();

      final store = InMemoryIdentityStore();
      await store.saveIdentity('alice', result.publicKey, result.secretKey);

      final pk = await store.getPublicKey('alice');
      expect(pk, isNotNull);
      expect(pk!.encapsulationKey, equals(result.publicKey.encapsulationKey));

      final sk = await store.getSecretKey('alice');
      expect(sk, isNotNull);
      expect(sk!.decapsulationKey, equals(result.secretKey.decapsulationKey));

      // Non-existent user returns null.
      expect(await store.getPublicKey('unknown'), isNull);
    });

    test('InMemoryPreKeyStore save and remove', () async {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final reg = const Registration(crypto);
      final aliceReg = reg.generate();
      final initiator = const Initiator(crypto);
      final preKeyResult = initiator.uploadPreKey(
        lpkA: aliceReg.publicKey,
        lskA: aliceReg.secretKey,
      );

      final store = InMemoryPreKeyStore();
      await store.savePreKey('alice', preKeyResult.preKey);

      final pk = await store.getPreKey('alice');
      expect(pk, isNotNull);
      expect(
        pk!.ephemeralPublicKey,
        equals(preKeyResult.preKey.ephemeralPublicKey),
      );

      await store.removePreKey('alice');
      expect(await store.getPreKey('alice'), isNull);
    });

    test('InMemorySessionStore save, list, and remove', () async {
      const crypto = CryptoProvider(level: SecurityLevel.l192);
      final result = _handshake(crypto);

      final store = InMemorySessionStore();
      final session = Session(
        sessionId: result.alice.sessionId,
        sessionKey: result.alice.sessionKey,
        localIdentity: 'alice',
        remoteIdentity: 'bob',
      );

      await store.saveSession('bob', session);

      final retrieved = await store.getSession('bob');
      expect(retrieved, isNotNull);
      expect(retrieved!.localIdentity, equals('alice'));
      expect(retrieved.remoteIdentity, equals('bob'));
      expect(retrieved.sessionKey, equals(result.alice.sessionKey));

      final all = await store.getAllSessions();
      expect(all.length, equals(1));

      await store.removeSession('bob');
      expect(await store.getSession('bob'), isNull);
      expect(await store.getAllSessions(), isEmpty);
    });
  });

  // ==========================================================================
  // 10. Crypto primitive sanity checks
  // ==========================================================================

  group('crypto primitive sanity checks', () {
    for (final level in SecurityLevel.values) {
      test('KEM encap/decap round-trip at ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final kp = crypto.kem.keyGen();
        final encResult = crypto.kem.encap(kp.publicKey);
        final decResult = crypto.kem.decap(kp.secretKey, encResult.ciphertext);
        expect(decResult, equals(encResult.sharedSecret));
      });

      test('SIG sign/verify round-trip at ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final kp = crypto.sig.keyGen();
        final message = Uint8List.fromList([1, 2, 3, 4, 5]);
        final sig = crypto.sig.sign(kp.signingKey, message);
        expect(crypto.sig.verify(kp.verificationKey, message, sig), isTrue);

        // Tampered message should fail verification.
        final tampered = Uint8List.fromList([5, 4, 3, 2, 1]);
        expect(crypto.sig.verify(kp.verificationKey, tampered, sig), isFalse);
      });

      test('PRF produces deterministic output at ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final input = Uint8List.fromList([10, 20, 30]);
        final out1 = crypto.prf.evaluate(key, input, 64);
        final out2 = crypto.prf.evaluate(key, input, 64);
        expect(out1, equals(out2));
      });

      test('Ext produces deterministic output at ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final salt = Uint8List.fromList(List.generate(32, (i) => i));
        final ikm = Uint8List.fromList([1, 2, 3]);
        final out1 = crypto.ext.extract(salt, ikm);
        final out2 = crypto.ext.extract(salt, ikm);
        expect(out1, equals(out2));
      });
    }
  });
}
