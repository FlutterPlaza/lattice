import 'dart:convert';
import 'dart:typed_data';

import 'package:lattice_server_firebase/lattice_server_firebase.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// In-memory Firestore adapter for testing
// ---------------------------------------------------------------------------

/// A simple in-memory implementation of [FirestoreAdapter] for unit tests.
class InMemoryFirestoreAdapter implements FirestoreAdapter {
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  int _autoIdCounter = 0;

  @override
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _collections.putIfAbsent(collection, () => {});
    _collections[collection]![documentId] = {...data, '_id': documentId};
  }

  @override
  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String documentId,
  ) async {
    return _collections[collection]?[documentId];
  }

  @override
  Future<List<Map<String, dynamic>>> getCollection(
    String collection, {
    String? whereField,
    String? whereValue,
  }) async {
    final docs = _collections[collection]?.values.toList() ?? [];
    if (whereField != null && whereValue != null) {
      return docs.where((d) => d[whereField] == whereValue).toList();
    }
    return docs;
  }

  @override
  Future<void> deleteDocument(String collection, String documentId) async {
    _collections[collection]?.remove(documentId);
  }

  @override
  Future<void> addDocument(String collection, Map<String, dynamic> data) async {
    _collections.putIfAbsent(collection, () => {});
    final id = 'auto_${_autoIdCounter++}';
    _collections[collection]![id] = {...data, '_id': id};
  }

  @override
  Future<int> countDocuments(String collection) async {
    return _collections[collection]?.length ?? 0;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // FirebaseConfig
  // ---------------------------------------------------------------------------
  group('FirebaseConfig', () {
    test('constructs with required fields and defaults', () {
      const config = FirebaseConfig(projectId: 'my-project');

      expect(config.projectId, equals('my-project'));
      expect(config.region, equals('us-central1'));
      expect(config.serviceName, equals('lattice-server'));
      expect(config.port, equals(8080));
      expect(config.minInstances, equals(0));
      expect(config.maxInstances, equals(3));
      expect(config.memory, equals('512Mi'));
      expect(config.cpu, equals('1'));
      expect(config.environment, isEmpty);
    });

    test('constructs with all custom values', () {
      const config = FirebaseConfig(
        projectId: 'custom-project',
        region: 'europe-west1',
        serviceName: 'custom-service',
        port: 9090,
        minInstances: 1,
        maxInstances: 10,
        memory: '1Gi',
        cpu: '2',
        environment: {'KEY': 'VALUE'},
      );

      expect(config.projectId, equals('custom-project'));
      expect(config.region, equals('europe-west1'));
      expect(config.serviceName, equals('custom-service'));
      expect(config.port, equals(9090));
      expect(config.minInstances, equals(1));
      expect(config.maxInstances, equals(10));
      expect(config.memory, equals('1Gi'));
      expect(config.cpu, equals('2'));
      expect(config.environment, equals({'KEY': 'VALUE'}));
    });

    test('toMap serialises all fields', () {
      const config = FirebaseConfig(
        projectId: 'test-project',
        region: 'asia-east1',
        environment: {'FOO': 'bar'},
      );

      final map = config.toMap();
      expect(map['project_id'], equals('test-project'));
      expect(map['region'], equals('asia-east1'));
      expect(map['service_name'], equals('lattice-server'));
      expect(map['port'], equals(8080));
      expect(map['min_instances'], equals(0));
      expect(map['max_instances'], equals(3));
      expect(map['memory'], equals('512Mi'));
      expect(map['cpu'], equals('1'));
      expect(map['environment'], equals({'FOO': 'bar'}));
    });

    test('fromMap round-trips with toMap', () {
      const original = FirebaseConfig(
        projectId: 'round-trip',
        region: 'us-west1',
        serviceName: 'my-svc',
        port: 3000,
        minInstances: 2,
        maxInstances: 8,
        memory: '2Gi',
        cpu: '4',
        environment: {'A': '1', 'B': '2'},
      );

      final restored = FirebaseConfig.fromMap(original.toMap());

      expect(restored.projectId, equals(original.projectId));
      expect(restored.region, equals(original.region));
      expect(restored.serviceName, equals(original.serviceName));
      expect(restored.port, equals(original.port));
      expect(restored.minInstances, equals(original.minInstances));
      expect(restored.maxInstances, equals(original.maxInstances));
      expect(restored.memory, equals(original.memory));
      expect(restored.cpu, equals(original.cpu));
      expect(restored.environment, equals(original.environment));
    });

    test('fromMap applies defaults for missing optional fields', () {
      final config = FirebaseConfig.fromMap({'project_id': 'minimal'});

      expect(config.projectId, equals('minimal'));
      expect(config.region, equals('us-central1'));
      expect(config.serviceName, equals('lattice-server'));
      expect(config.port, equals(8080));
      expect(config.minInstances, equals(0));
      expect(config.maxInstances, equals(3));
      expect(config.memory, equals('512Mi'));
      expect(config.cpu, equals('1'));
      expect(config.environment, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // FirebaseDeployer
  // ---------------------------------------------------------------------------
  group('FirebaseDeployer', () {
    late FirebaseDeployer deployer;

    setUp(() {
      deployer = const FirebaseDeployer(
        FirebaseConfig(
          projectId: 'test-project',
          region: 'us-central1',
          serviceName: 'lattice-server',
          port: 8080,
          minInstances: 0,
          maxInstances: 3,
          memory: '512Mi',
          cpu: '1',
        ),
      );
    });

    test('generateFirebaseJson contains correct service config', () {
      final json = deployer.generateFirebaseJson();
      final parsed = jsonDecode(json) as Map<String, dynamic>;

      expect(parsed.containsKey('hosting'), isTrue);
      final hosting = parsed['hosting'] as Map<String, dynamic>;
      expect(hosting['public'], equals('public'));

      final rewrites = hosting['rewrites'] as List<dynamic>;
      expect(rewrites, hasLength(1));

      final rewrite = rewrites[0] as Map<String, dynamic>;
      expect(rewrite['source'], equals('/api/**'));

      final run = rewrite['run'] as Map<String, dynamic>;
      expect(run['serviceId'], equals('lattice-server'));
      expect(run['region'], equals('us-central1'));
    });

    test('generateFirebaseJson uses custom service name and region', () {
      final customDeployer = const FirebaseDeployer(
        FirebaseConfig(
          projectId: 'custom',
          region: 'europe-west1',
          serviceName: 'my-service',
        ),
      );

      final json = customDeployer.generateFirebaseJson();
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final hosting = parsed['hosting'] as Map<String, dynamic>;
      final rewrites = hosting['rewrites'] as List<dynamic>;
      final run =
          (rewrites[0] as Map<String, dynamic>)['run'] as Map<String, dynamic>;

      expect(run['serviceId'], equals('my-service'));
      expect(run['region'], equals('europe-west1'));
    });

    test('generateDeployCommands returns three commands', () {
      final commands = deployer.generateDeployCommands();
      expect(commands, hasLength(3));
    });

    test('generateDeployCommands includes gcloud builds submit', () {
      final commands = deployer.generateDeployCommands();
      expect(commands[0], contains('gcloud builds submit'));
      expect(commands[0], contains('gcr.io/test-project/lattice-server'));
    });

    test('generateDeployCommands includes gcloud run deploy', () {
      final commands = deployer.generateDeployCommands();
      expect(commands[1], contains('gcloud run deploy lattice-server'));
      expect(commands[1], contains('--platform managed'));
      expect(commands[1], contains('--region us-central1'));
      expect(commands[1], contains('--port 8080'));
      expect(commands[1], contains('--min-instances 0'));
      expect(commands[1], contains('--max-instances 3'));
      expect(commands[1], contains('--memory 512Mi'));
      expect(commands[1], contains('--cpu 1'));
    });

    test('generateDeployCommands includes firebase deploy', () {
      final commands = deployer.generateDeployCommands();
      expect(commands[2], equals('firebase deploy --only hosting'));
    });

    test('generateDeployCommands includes env vars when set', () {
      final envDeployer = const FirebaseDeployer(
        FirebaseConfig(
          projectId: 'env-test',
          environment: {'API_KEY': 'secret', 'MODE': 'production'},
        ),
      );

      final commands = envDeployer.generateDeployCommands();
      expect(commands[1], contains('--set-env-vars'));
      expect(commands[1], contains('API_KEY=secret'));
      expect(commands[1], contains('MODE=production'));
    });

    test('deploy with dryRun returns preview', () async {
      final result = await deployer.deploy(dryRun: true);
      expect(result.success, isTrue);
      expect(result.message, contains('Dry-run'));
      expect(result.message, contains('gcloud builds submit'));
      expect(result.message, contains('gcloud run deploy'));
      expect(result.message, contains('firebase deploy'));
    });

    test('FirebaseDeployResult toString formats correctly', () {
      const success = FirebaseDeployResult(
        success: true,
        message: 'Done.',
        serviceUrl: 'https://example.run.app',
      );
      expect(
        success.toString(),
        equals('[SUCCESS] Done. (https://example.run.app)'),
      );

      const failure = FirebaseDeployResult(success: false, message: 'Failed.');
      expect(failure.toString(), equals('[FAILURE] Failed.'));
    });
  });

  // ---------------------------------------------------------------------------
  // FirestoreStorage
  // ---------------------------------------------------------------------------
  group('FirestoreStorage', () {
    late InMemoryFirestoreAdapter adapter;
    late FirestoreStorage storage;

    setUp(() {
      adapter = InMemoryFirestoreAdapter();
      storage = FirestoreStorage(adapter);
    });

    // -- Users ----------------------------------------------------------------
    group('users', () {
      test('registerUser stores and retrieves a user', () async {
        final publicKey = Uint8List.fromList([1, 2, 3]);
        await storage.registerUser('alice', publicKey);

        final retrieved = await storage.getUserPublicKey('alice');
        expect(retrieved, isNotNull);
        expect(retrieved, equals([1, 2, 3]));
      });

      test('registerUser throws on duplicate userId', () async {
        final publicKey = Uint8List.fromList([1, 2, 3]);
        await storage.registerUser('alice', publicKey);

        expect(
          () => storage.registerUser('alice', publicKey),
          throwsA(isA<StateError>()),
        );
      });

      test('getUserPublicKey returns null for unknown user', () async {
        final result = await storage.getUserPublicKey('unknown');
        expect(result, isNull);
      });

      test('getUserCount returns correct count', () async {
        expect(await storage.getUserCount(), equals(0));

        await storage.registerUser('alice', Uint8List(0));
        expect(await storage.getUserCount(), equals(1));

        await storage.registerUser('bob', Uint8List(0));
        expect(await storage.getUserCount(), equals(2));
      });
    });

    // -- Pre-keys -------------------------------------------------------------
    group('prekeys', () {
      test('storePreKey and getPreKey round-trip', () async {
        final bundle = Uint8List.fromList([10, 20, 30]);
        await storage.storePreKey('alice', bundle);

        final retrieved = await storage.getPreKey('alice');
        expect(retrieved, isNotNull);
        expect(retrieved, equals([10, 20, 30]));
      });

      test('storePreKey replaces existing prekey', () async {
        await storage.storePreKey('alice', Uint8List.fromList([1]));
        await storage.storePreKey('alice', Uint8List.fromList([2]));

        final retrieved = await storage.getPreKey('alice');
        expect(retrieved, equals([2]));
      });

      test('getPreKey returns null for unknown user', () async {
        final result = await storage.getPreKey('unknown');
        expect(result, isNull);
      });

      test('removePreKey removes the prekey', () async {
        await storage.storePreKey('alice', Uint8List(0));
        await storage.removePreKey('alice');
        expect(await storage.getPreKey('alice'), isNull);
      });

      test('getPreKeyCount returns correct count', () async {
        expect(await storage.getPreKeyCount(), equals(0));

        await storage.storePreKey('alice', Uint8List(0));
        expect(await storage.getPreKeyCount(), equals(1));

        await storage.storePreKey('bob', Uint8List(0));
        expect(await storage.getPreKeyCount(), equals(2));
      });
    });

    // -- Messages -------------------------------------------------------------
    group('messages', () {
      test('storeMessage and getMessages round-trip', () async {
        final msgData = Uint8List.fromList([100, 200]);
        await storage.storeMessage('alice', 'bob', msgData);

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
        await storage.storeMessage('alice', 'bob', Uint8List.fromList([1]));
        await storage.storeMessage('alice', 'charlie', Uint8List.fromList([2]));

        final messages = await storage.getMessages('alice');
        expect(messages, hasLength(2));
      });

      test('clearMessages removes all messages for user', () async {
        await storage.storeMessage('alice', 'bob', Uint8List(0));
        await storage.storeMessage('alice', 'charlie', Uint8List(0));
        await storage.clearMessages('alice');

        final messages = await storage.getMessages('alice');
        expect(messages, isEmpty);
      });

      test('clearMessages does not affect other users', () async {
        await storage.storeMessage('alice', 'bob', Uint8List(0));
        await storage.storeMessage('bob', 'alice', Uint8List(0));
        await storage.clearMessages('alice');

        final bobMessages = await storage.getMessages('bob');
        expect(bobMessages, hasLength(1));
      });

      test('getMessageCount returns total across all recipients', () async {
        expect(await storage.getMessageCount(), equals(0));

        await storage.storeMessage('alice', 'bob', Uint8List(0));
        await storage.storeMessage('charlie', 'bob', Uint8List(0));
        expect(await storage.getMessageCount(), equals(2));
      });
    });

    // -- Adapter pattern validation -------------------------------------------
    group('adapter pattern', () {
      test('InMemoryFirestoreAdapter implements all interface methods', () {
        // Validates that the adapter correctly implements the abstract class.
        expect(adapter, isA<FirestoreAdapter>());
      });

      test('adapter setDocument and getDocument round-trip', () async {
        await adapter.setDocument('test_col', 'doc1', {'key': 'value'});
        final doc = await adapter.getDocument('test_col', 'doc1');
        expect(doc, isNotNull);
        expect(doc!['key'], equals('value'));
      });

      test('adapter getCollection with filter', () async {
        await adapter.addDocument('items', {'type': 'a', 'value': '1'});
        await adapter.addDocument('items', {'type': 'b', 'value': '2'});
        await adapter.addDocument('items', {'type': 'a', 'value': '3'});

        final filtered = await adapter.getCollection(
          'items',
          whereField: 'type',
          whereValue: 'a',
        );
        expect(filtered, hasLength(2));
      });

      test('adapter countDocuments returns correct count', () async {
        expect(await adapter.countDocuments('empty'), equals(0));

        await adapter.addDocument('counting', {'x': 1});
        await adapter.addDocument('counting', {'x': 2});
        expect(await adapter.countDocuments('counting'), equals(2));
      });

      test('adapter deleteDocument removes the document', () async {
        await adapter.setDocument('col', 'id1', {'data': 'hello'});
        await adapter.deleteDocument('col', 'id1');
        final doc = await adapter.getDocument('col', 'id1');
        expect(doc, isNull);
      });
    });
  });
}
