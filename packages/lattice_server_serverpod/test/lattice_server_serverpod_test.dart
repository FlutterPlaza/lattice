import 'dart:convert';
import 'dart:typed_data';

import 'package:lattice_server_serverpod/lattice_server_serverpod.dart';
import 'package:test/test.dart';

/// In-memory implementation of [DatabaseAdapter] for testing.
class InMemoryDatabaseAdapter implements DatabaseAdapter {
  final Map<String, List<Map<String, dynamic>>> _tables = {};

  List<Map<String, dynamic>> _table(String name) =>
      _tables.putIfAbsent(name, () => []);

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    _table(table).add(Map<String, dynamic>.from(values));
  }

  @override
  Future<Map<String, dynamic>?> findOne(
    String table,
    String key,
    String value,
  ) async {
    final rows = _table(table);
    for (final row in rows) {
      if (row[key] == value) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> findAll(
    String table, {
    String? whereKey,
    String? whereValue,
  }) async {
    final rows = _table(table);
    if (whereKey != null && whereValue != null) {
      return rows
          .where((row) => row[whereKey] == whereValue)
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return rows.map(Map<String, dynamic>.from).toList();
  }

  @override
  Future<void> delete(String table, String key, String value) async {
    _table(table).removeWhere((row) => row[key] == value);
  }

  @override
  Future<int> count(String table) async => _table(table).length;
}

void main() {
  group('ServerpodStorage', () {
    late InMemoryDatabaseAdapter db;
    late ServerpodStorage storage;

    setUp(() {
      db = InMemoryDatabaseAdapter();
      storage = ServerpodStorage(db);
    });

    group('user operations', () {
      test('register and retrieve user public key', () async {
        final publicKey = Uint8List.fromList([1, 2, 3, 4, 5]);
        await storage.registerUser('alice', publicKey);

        final retrieved = await storage.getUserPublicKey('alice');
        expect(retrieved, isNotNull);
        expect(retrieved, equals(publicKey));
      });

      test('returns null for unknown user', () async {
        final result = await storage.getUserPublicKey('unknown');
        expect(result, isNull);
      });

      test('duplicate user is detectable via getUserPublicKey', () async {
        final publicKey = Uint8List.fromList([1, 2, 3]);
        await storage.registerUser('alice', publicKey);

        // The storage itself does not throw, but the endpoint handler
        // checks for duplicates via getUserPublicKey before registering.
        final existing = await storage.getUserPublicKey('alice');
        expect(existing, isNotNull);
      });
    });

    group('pre-key operations', () {
      test('store and retrieve pre-key bundle', () async {
        final bundle = Uint8List.fromList([10, 20, 30, 40]);
        await storage.storePreKey('alice', bundle);

        final retrieved = await storage.getPreKey('alice');
        expect(retrieved, isNotNull);
        expect(retrieved, equals(bundle));
      });

      test('returns null for missing pre-key', () async {
        final result = await storage.getPreKey('unknown');
        expect(result, isNull);
      });

      test('remove pre-key', () async {
        final bundle = Uint8List.fromList([10, 20, 30]);
        await storage.storePreKey('alice', bundle);
        await storage.removePreKey('alice');

        final result = await storage.getPreKey('alice');
        expect(result, isNull);
      });

      test('store pre-key replaces existing', () async {
        final bundle1 = Uint8List.fromList([1, 2, 3]);
        final bundle2 = Uint8List.fromList([4, 5, 6]);
        await storage.storePreKey('alice', bundle1);
        await storage.storePreKey('alice', bundle2);

        final retrieved = await storage.getPreKey('alice');
        expect(retrieved, equals(bundle2));
      });
    });

    group('message operations', () {
      test('store and retrieve messages', () async {
        final msg1 = Uint8List.fromList([100, 101]);
        final msg2 = Uint8List.fromList([200, 201]);
        await storage.storeMessage('alice', 'bob', msg1);
        await storage.storeMessage('alice', 'carol', msg2);

        final messages = await storage.getMessages('alice');
        expect(messages, hasLength(2));
        expect(messages[0].senderId, equals('bob'));
        expect(messages[0].messageData, equals(msg1));
        expect(messages[1].senderId, equals('carol'));
        expect(messages[1].messageData, equals(msg2));
      });

      test('returns empty list for user with no messages', () async {
        final messages = await storage.getMessages('unknown');
        expect(messages, isEmpty);
      });

      test('clear messages', () async {
        final msg = Uint8List.fromList([1, 2, 3]);
        await storage.storeMessage('alice', 'bob', msg);
        await storage.clearMessages('alice');

        final messages = await storage.getMessages('alice');
        expect(messages, isEmpty);
      });
    });

    group('counts', () {
      test('user count', () async {
        expect(await storage.getUserCount(), equals(0));
        await storage.registerUser('alice', Uint8List.fromList([1]));
        expect(await storage.getUserCount(), equals(1));
        await storage.registerUser('bob', Uint8List.fromList([2]));
        expect(await storage.getUserCount(), equals(2));
      });

      test('pre-key count', () async {
        expect(await storage.getPreKeyCount(), equals(0));
        await storage.storePreKey('alice', Uint8List.fromList([1]));
        expect(await storage.getPreKeyCount(), equals(1));
      });

      test('message count', () async {
        expect(await storage.getMessageCount(), equals(0));
        await storage.storeMessage('alice', 'bob', Uint8List.fromList([1]));
        await storage.storeMessage('alice', 'carol', Uint8List.fromList([2]));
        expect(await storage.getMessageCount(), equals(2));
      });
    });
  });

  group('ServerpodEndpointHandlers', () {
    late InMemoryDatabaseAdapter db;
    late ServerpodStorage storage;
    late ServerpodEndpointHandlers handlers;

    setUp(() {
      db = InMemoryDatabaseAdapter();
      storage = ServerpodStorage(db);
      handlers = ServerpodEndpointHandlers();
    });

    test('register creates a new user', () async {
      final publicKey = base64Encode([1, 2, 3, 4, 5]);
      final result = await handlers.register(storage, 'alice', publicKey);

      expect(result['status'], equals('registered'));
      expect(result['userId'], equals('alice'));

      final stored = await storage.getUserPublicKey('alice');
      expect(stored, isNotNull);
    });

    test('register rejects duplicate user', () async {
      final publicKey = base64Encode([1, 2, 3]);
      await handlers.register(storage, 'alice', publicKey);

      expect(
        () => handlers.register(storage, 'alice', publicKey),
        throwsStateError,
      );
    });

    test('uploadPreKey stores a bundle', () async {
      final bundle = base64Encode([10, 20, 30]);
      final result = await handlers.uploadPreKey(storage, 'alice', bundle);

      expect(result['status'], equals('stored'));
      expect(result['userId'], equals('alice'));
    });

    test('getPreKey returns bundle and removes it', () async {
      final bundleBytes = Uint8List.fromList([10, 20, 30]);
      final bundleB64 = base64Encode(bundleBytes);
      await handlers.uploadPreKey(storage, 'alice', bundleB64);

      final result = await handlers.getPreKey(storage, 'alice');
      expect(result, isNotNull);
      expect(result!['userId'], equals('alice'));
      expect(result['bundle'], equals(bundleB64));

      // Pre-key should be removed after retrieval.
      final afterRetrieval = await handlers.getPreKey(storage, 'alice');
      expect(afterRetrieval, isNull);
    });

    test('getPreKey returns null for missing user', () async {
      final result = await handlers.getPreKey(storage, 'unknown');
      expect(result, isNull);
    });

    test('sendMessage stores a message', () async {
      final message = base64Encode([100, 101, 102]);
      final result = await handlers.sendMessage(
        storage,
        'alice',
        'bob',
        message,
      );

      expect(result['status'], equals('delivered'));
    });

    test('getMessages returns messages and clears them', () async {
      final msg1 = base64Encode([1, 2, 3]);
      final msg2 = base64Encode([4, 5, 6]);
      await handlers.sendMessage(storage, 'alice', 'bob', msg1);
      await handlers.sendMessage(storage, 'alice', 'carol', msg2);

      final messages = await handlers.getMessages(storage, 'alice');
      expect(messages, hasLength(2));
      expect(messages[0]['senderId'], equals('bob'));
      expect(messages[0]['message'], equals(msg1));
      expect(messages[1]['senderId'], equals('carol'));
      expect(messages[1]['message'], equals(msg2));

      // Messages should be cleared after retrieval.
      final afterRetrieval = await handlers.getMessages(storage, 'alice');
      expect(afterRetrieval, isEmpty);
    });

    test('health returns status and version', () {
      final result = handlers.health();

      expect(result['status'], equals('ok'));
      expect(result['uptime'], isA<int>());
      expect(result['version'], equals('0.1.0'));
    });

    test('metrics returns counts and uptime', () async {
      await storage.registerUser('alice', Uint8List.fromList([1]));
      await storage.storePreKey('alice', Uint8List.fromList([2]));
      await storage.storeMessage('alice', 'bob', Uint8List.fromList([3]));

      final result = await handlers.metrics(storage);

      expect(result['users'], equals(1));
      expect(result['prekeys'], equals(1));
      expect(result['pendingMessages'], equals(1));
      expect(result['uptime'], isA<int>());
    });
  });

  group('Migration', () {
    test('createTables SQL is non-empty and contains expected tables', () {
      expect(Migration.createTables, isNotEmpty);
      expect(Migration.createTables, contains('lattice_users'));
      expect(Migration.createTables, contains('lattice_prekeys'));
      expect(Migration.createTables, contains('lattice_messages'));
      expect(Migration.createTables, contains('CREATE TABLE'));
      expect(Migration.createTables, contains('CREATE INDEX'));
    });

    test('dropTables SQL is non-empty and contains expected tables', () {
      expect(Migration.dropTables, isNotEmpty);
      expect(Migration.dropTables, contains('lattice_users'));
      expect(Migration.dropTables, contains('lattice_prekeys'));
      expect(Migration.dropTables, contains('lattice_messages'));
      expect(Migration.dropTables, contains('DROP TABLE'));
    });
  });
}
