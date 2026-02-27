import 'dart:typed_data';

import 'package:lattice_server_supabase/lattice_server_supabase.dart';
import 'package:test/test.dart';

/// In-memory implementation of [SupabaseAdapter] for testing.
///
/// Simulates a PostgREST-like table store using in-memory maps.
class InMemorySupabaseAdapter implements SupabaseAdapter {
  final Map<String, List<Map<String, dynamic>>> _tables = {};

  List<Map<String, dynamic>> _table(String name) =>
      _tables.putIfAbsent(name, () => []);

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    _table(table).add(Map<String, dynamic>.from(values));
  }

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    Map<String, String>? filters,
  }) async {
    final rows = _table(table);
    if (filters == null || filters.isEmpty) {
      return List<Map<String, dynamic>>.from(rows);
    }
    return rows.where((row) {
      return filters.entries.every((f) => row[f.key]?.toString() == f.value);
    }).toList();
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> values,
    String matchKey,
    String matchValue,
  ) async {
    for (final row in _table(table)) {
      if (row[matchKey]?.toString() == matchValue) {
        row.addAll(values);
      }
    }
  }

  @override
  Future<void> delete(String table, String matchKey, String matchValue) async {
    _table(table).removeWhere((row) => row[matchKey]?.toString() == matchValue);
  }

  @override
  Future<int> count(String table) async => _table(table).length;
}

void main() {
  late InMemorySupabaseAdapter adapter;
  late SupabaseStorage storage;

  setUp(() {
    adapter = InMemorySupabaseAdapter();
    storage = SupabaseStorage(adapter);
  });

  group('SupabaseStorage users', () {
    test('registerUser and getUserPublicKey round-trip', () async {
      final publicKey = Uint8List.fromList([1, 2, 3, 4, 5]);
      await storage.registerUser('alice', publicKey);

      final retrieved = await storage.getUserPublicKey('alice');
      expect(retrieved, isNotNull);
      expect(retrieved, equals(publicKey));
    });

    test('getUserPublicKey returns null for unknown user', () async {
      final result = await storage.getUserPublicKey('unknown');
      expect(result, isNull);
    });

    test('registerUser throws on duplicate', () async {
      final publicKey = Uint8List.fromList([1, 2, 3]);
      await storage.registerUser('alice', publicKey);

      expect(() => storage.registerUser('alice', publicKey), throwsStateError);
    });

    test('getUserCount reflects registered users', () async {
      expect(await storage.getUserCount(), equals(0));

      await storage.registerUser('alice', Uint8List.fromList([1]));
      expect(await storage.getUserCount(), equals(1));

      await storage.registerUser('bob', Uint8List.fromList([2]));
      expect(await storage.getUserCount(), equals(2));
    });
  });

  group('SupabaseStorage prekeys', () {
    test('storePreKey and getPreKey round-trip', () async {
      final bundle = Uint8List.fromList([10, 20, 30]);
      await storage.storePreKey('alice', bundle);

      final retrieved = await storage.getPreKey('alice');
      expect(retrieved, isNotNull);
      expect(retrieved, equals(bundle));
    });

    test('getPreKey returns null when no pre-key exists', () async {
      final result = await storage.getPreKey('unknown');
      expect(result, isNull);
    });

    test('storePreKey replaces existing pre-key', () async {
      final bundle1 = Uint8List.fromList([10, 20, 30]);
      final bundle2 = Uint8List.fromList([40, 50, 60]);

      await storage.storePreKey('alice', bundle1);
      await storage.storePreKey('alice', bundle2);

      final retrieved = await storage.getPreKey('alice');
      expect(retrieved, equals(bundle2));
    });

    test('removePreKey deletes the pre-key', () async {
      final bundle = Uint8List.fromList([10, 20, 30]);
      await storage.storePreKey('alice', bundle);

      await storage.removePreKey('alice');
      final result = await storage.getPreKey('alice');
      expect(result, isNull);
    });

    test('removePreKey is safe for non-existent user', () async {
      // Should not throw.
      await storage.removePreKey('unknown');
    });

    test('getPreKeyCount reflects stored bundles', () async {
      expect(await storage.getPreKeyCount(), equals(0));

      await storage.storePreKey('alice', Uint8List.fromList([1]));
      expect(await storage.getPreKeyCount(), equals(1));

      await storage.storePreKey('bob', Uint8List.fromList([2]));
      expect(await storage.getPreKeyCount(), equals(2));

      await storage.removePreKey('alice');
      expect(await storage.getPreKeyCount(), equals(1));
    });
  });

  group('SupabaseStorage messages', () {
    test('storeMessage and getMessages round-trip', () async {
      final msg = Uint8List.fromList([100, 101, 102]);
      await storage.storeMessage('bob', 'alice', msg);

      final messages = await storage.getMessages('bob');
      expect(messages, hasLength(1));
      expect(messages.first.senderId, equals('alice'));
      expect(messages.first.messageData, equals(msg));
    });

    test('getMessages returns empty list for no messages', () async {
      final messages = await storage.getMessages('unknown');
      expect(messages, isEmpty);
    });

    test('storeMessage accumulates multiple messages', () async {
      final msg1 = Uint8List.fromList([1]);
      final msg2 = Uint8List.fromList([2]);
      final msg3 = Uint8List.fromList([3]);

      await storage.storeMessage('bob', 'alice', msg1);
      await storage.storeMessage('bob', 'carol', msg2);
      await storage.storeMessage('bob', 'alice', msg3);

      final messages = await storage.getMessages('bob');
      expect(messages, hasLength(3));
    });

    test('clearMessages removes all messages for a user', () async {
      await storage.storeMessage('bob', 'alice', Uint8List.fromList([1]));
      await storage.storeMessage('bob', 'carol', Uint8List.fromList([2]));

      await storage.clearMessages('bob');
      final messages = await storage.getMessages('bob');
      expect(messages, isEmpty);
    });

    test('clearMessages does not affect other users', () async {
      await storage.storeMessage('bob', 'alice', Uint8List.fromList([1]));
      await storage.storeMessage('carol', 'alice', Uint8List.fromList([2]));

      await storage.clearMessages('bob');

      final bobMessages = await storage.getMessages('bob');
      final carolMessages = await storage.getMessages('carol');
      expect(bobMessages, isEmpty);
      expect(carolMessages, hasLength(1));
    });

    test('clearMessages is safe for non-existent user', () async {
      // Should not throw.
      await storage.clearMessages('unknown');
    });

    test('getMessageCount reflects total messages', () async {
      expect(await storage.getMessageCount(), equals(0));

      await storage.storeMessage('bob', 'alice', Uint8List.fromList([1]));
      expect(await storage.getMessageCount(), equals(1));

      await storage.storeMessage('carol', 'alice', Uint8List.fromList([2]));
      expect(await storage.getMessageCount(), equals(2));

      await storage.clearMessages('bob');
      expect(await storage.getMessageCount(), equals(1));
    });
  });

  group('SupabaseConfig', () {
    test('constructor sets all fields', () {
      const config = SupabaseConfig(
        projectUrl: 'https://abc.supabase.co',
        anonKey: 'anon-key-123',
        serviceRoleKey: 'service-key-456',
      );

      expect(config.projectUrl, equals('https://abc.supabase.co'));
      expect(config.anonKey, equals('anon-key-123'));
      expect(config.serviceRoleKey, equals('service-key-456'));
    });

    test('constructor allows null serviceRoleKey', () {
      const config = SupabaseConfig(
        projectUrl: 'https://abc.supabase.co',
        anonKey: 'anon-key-123',
      );

      expect(config.serviceRoleKey, isNull);
    });
  });

  group('SupabaseMigration', () {
    test('createTables SQL contains all expected table names', () {
      expect(SupabaseMigration.createTables, contains('lattice_users'));
      expect(SupabaseMigration.createTables, contains('lattice_prekeys'));
      expect(SupabaseMigration.createTables, contains('lattice_messages'));
    });

    test('createTables SQL contains index creation', () {
      expect(
        SupabaseMigration.createTables,
        contains('idx_lattice_messages_recipient'),
      );
    });

    test('createTables SQL contains RLS comments', () {
      expect(SupabaseMigration.createTables, contains('ROW LEVEL SECURITY'));
    });

    test('dropTables SQL drops all tables', () {
      expect(
        SupabaseMigration.dropTables,
        contains('DROP TABLE IF EXISTS lattice_messages'),
      );
      expect(
        SupabaseMigration.dropTables,
        contains('DROP TABLE IF EXISTS lattice_prekeys'),
      );
      expect(
        SupabaseMigration.dropTables,
        contains('DROP TABLE IF EXISTS lattice_users'),
      );
    });
  });
}
