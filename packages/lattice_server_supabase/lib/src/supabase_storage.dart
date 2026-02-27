import 'dart:convert';
import 'dart:typed_data';

/// Abstract Supabase client adapter.
///
/// This decouples the storage implementation from any specific HTTP or
/// Supabase SDK dependency. Implement it using the `supabase` package or
/// raw HTTP calls against the PostgREST API.
///
/// Example using the `supabase` package:
/// ```dart
/// class SupabaseClientAdapter implements SupabaseAdapter {
///   final SupabaseClient client;
///   SupabaseClientAdapter(this.client);
///
///   @override
///   Future<void> insert(
///     String table,
///     Map<String, dynamic> values,
///   ) async {
///     await client.from(table).insert(values);
///   }
///
///   @override
///   Future<List<Map<String, dynamic>>> select(
///     String table, {
///     Map<String, String>? filters,
///   }) async {
///     var query = client.from(table).select();
///     filters?.forEach((key, value) {
///       query = query.eq(key, value);
///     });
///     return await query;
///   }
///
///   @override
///   Future<void> update(
///     String table,
///     Map<String, dynamic> values,
///     String matchKey,
///     String matchValue,
///   ) async {
///     await client.from(table).update(values).eq(matchKey, matchValue);
///   }
///
///   @override
///   Future<void> delete(
///     String table,
///     String matchKey,
///     String matchValue,
///   ) async {
///     await client.from(table).delete().eq(matchKey, matchValue);
///   }
///
///   @override
///   Future<int> count(String table) async {
///     final result = await client.from(table).select().count();
///     return result.count;
///   }
/// }
/// ```
abstract class SupabaseAdapter {
  /// Inserts a row into [table] with the given [values].
  Future<void> insert(String table, Map<String, dynamic> values);

  /// Selects rows from [table], optionally filtered by equality [filters].
  Future<List<Map<String, dynamic>>> select(
    String table, {
    Map<String, String>? filters,
  });

  /// Updates rows in [table] where [matchKey] equals [matchValue].
  Future<void> update(
    String table,
    Map<String, dynamic> values,
    String matchKey,
    String matchValue,
  );

  /// Deletes rows from [table] where [matchKey] equals [matchValue].
  Future<void> delete(String table, String matchKey, String matchValue);

  /// Returns the total row count for [table].
  Future<int> count(String table);
}

/// Supabase-backed storage for the Lattice key distribution server.
///
/// Stores users, pre-key bundles, and pending messages in three PostgreSQL
/// tables: `lattice_users`, `lattice_prekeys`, and `lattice_messages`.
///
/// Binary data (public keys, bundles, messages) is stored as base64-encoded
/// text columns for compatibility with PostgREST / Supabase.
class SupabaseStorage {
  /// Creates a [SupabaseStorage] backed by the given [adapter].
  const SupabaseStorage(this.adapter);

  /// The underlying Supabase adapter used for database operations.
  final SupabaseAdapter adapter;

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  /// Registers a new user with the given [userId] and [publicKeyData].
  ///
  /// Throws [StateError] if a user with the same [userId] already exists.
  Future<void> registerUser(String userId, Uint8List publicKeyData) async {
    final existing = await adapter.select(
      'lattice_users',
      filters: {'user_id': userId},
    );
    if (existing.isNotEmpty) {
      throw StateError('User "$userId" already registered');
    }
    await adapter.insert('lattice_users', {
      'user_id': userId,
      'public_key': base64Encode(publicKeyData),
      'registered_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Returns the public key bytes for [userId], or `null` if not found.
  Future<Uint8List?> getUserPublicKey(String userId) async {
    final rows = await adapter.select(
      'lattice_users',
      filters: {'user_id': userId},
    );
    if (rows.isEmpty) return null;
    return base64Decode(rows.first['public_key'] as String);
  }

  // ---------------------------------------------------------------------------
  // Pre-keys
  // ---------------------------------------------------------------------------

  /// Stores (or replaces) a pre-key bundle for [userId].
  Future<void> storePreKey(String userId, Uint8List bundleData) async {
    final existing = await adapter.select(
      'lattice_prekeys',
      filters: {'user_id': userId},
    );
    if (existing.isNotEmpty) {
      await adapter.update(
        'lattice_prekeys',
        {
          'bundle_data': base64Encode(bundleData),
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        },
        'user_id',
        userId,
      );
    } else {
      await adapter.insert('lattice_prekeys', {
        'user_id': userId,
        'bundle_data': base64Encode(bundleData),
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Returns the pre-key bundle bytes for [userId], or `null` if none exists.
  Future<Uint8List?> getPreKey(String userId) async {
    final rows = await adapter.select(
      'lattice_prekeys',
      filters: {'user_id': userId},
    );
    if (rows.isEmpty) return null;
    return base64Decode(rows.first['bundle_data'] as String);
  }

  /// Removes the pre-key bundle for [userId].
  Future<void> removePreKey(String userId) async {
    await adapter.delete('lattice_prekeys', 'user_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Stores a pending message from [senderId] to [recipientId].
  Future<void> storeMessage(
    String recipientId,
    String senderId,
    Uint8List messageData,
  ) async {
    await adapter.insert('lattice_messages', {
      'recipient_id': recipientId,
      'sender_id': senderId,
      'message_data': base64Encode(messageData),
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Returns all pending messages for [userId].
  Future<List<({String senderId, Uint8List messageData})>> getMessages(
    String userId,
  ) async {
    final rows = await adapter.select(
      'lattice_messages',
      filters: {'recipient_id': userId},
    );
    return rows.map((row) {
      return (
        senderId: row['sender_id'] as String,
        messageData: base64Decode(row['message_data'] as String),
      );
    }).toList();
  }

  /// Removes all pending messages for [userId].
  Future<void> clearMessages(String userId) async {
    await adapter.delete('lattice_messages', 'recipient_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  /// Returns the total number of registered users.
  Future<int> getUserCount() async => adapter.count('lattice_users');

  /// Returns the total number of stored pre-key bundles.
  Future<int> getPreKeyCount() async => adapter.count('lattice_prekeys');

  /// Returns the total number of pending messages.
  Future<int> getMessageCount() async => adapter.count('lattice_messages');
}
