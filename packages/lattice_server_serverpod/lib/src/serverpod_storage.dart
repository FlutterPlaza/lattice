import 'dart:convert';
import 'dart:typed_data';

/// Abstract database adapter for Serverpod integration.
///
/// Users implement this interface using Serverpod's database API:
/// ```dart
/// class ServerpodDatabaseAdapter implements DatabaseAdapter {
///   final Session session;
///   ServerpodDatabaseAdapter(this.session);
///
///   @override
///   Future<Map<String, dynamic>?> findOne(
///     String table, String key, String value,
///   ) async {
///     // Use session.db.findFirstRow(...)
///   }
///   // ...
/// }
/// ```
abstract class DatabaseAdapter {
  /// Inserts a new row into [table] with the given column [values].
  Future<void> insert(String table, Map<String, dynamic> values);

  /// Finds a single row in [table] where [key] equals [value].
  ///
  /// Returns `null` if no matching row is found.
  Future<Map<String, dynamic>?> findOne(String table, String key, String value);

  /// Finds all rows in [table], optionally filtering where
  /// [whereKey] equals [whereValue].
  Future<List<Map<String, dynamic>>> findAll(
    String table, {
    String? whereKey,
    String? whereValue,
  });

  /// Deletes rows from [table] where [key] equals [value].
  Future<void> delete(String table, String key, String value);

  /// Returns the total number of rows in [table].
  Future<int> count(String table);
}

/// Storage implementation using a [DatabaseAdapter] (for Serverpod PostgreSQL).
///
/// This class mirrors the operations of the Lattice `Storage` interface but
/// is designed to work with a relational database through the abstract
/// [DatabaseAdapter] layer. Users provide a concrete adapter backed by
/// Serverpod's session-based database API.
class ServerpodStorage {
  /// Creates a [ServerpodStorage] backed by the given [db] adapter.
  const ServerpodStorage(this.db);

  /// The database adapter used for all operations.
  final DatabaseAdapter db;

  // ---------------------------------------------------------------------------
  // User operations
  // ---------------------------------------------------------------------------

  /// Registers a new user with the given [userId] and [publicKeyData].
  ///
  /// The [publicKeyData] should be a serialized [LongTermPublicKey].
  Future<void> registerUser(String userId, Uint8List publicKeyData) async {
    await db.insert('lattice_users', {
      'user_id': userId,
      'public_key': _encodeBytes(publicKeyData),
      'registered_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns the serialized public key for [userId], or `null` if not found.
  Future<Uint8List?> getUserPublicKey(String userId) async {
    final row = await db.findOne('lattice_users', 'user_id', userId);
    if (row == null) return null;
    return _decodeBytes(row['public_key'] as String);
  }

  // ---------------------------------------------------------------------------
  // Pre-key operations
  // ---------------------------------------------------------------------------

  /// Stores (or replaces) a pre-key bundle for [userId].
  ///
  /// The [bundleData] should be a serialized [PreKeyBundle].
  Future<void> storePreKey(String userId, Uint8List bundleData) async {
    // Remove any existing pre-key first to emulate upsert.
    final existing = await db.findOne('lattice_prekeys', 'user_id', userId);
    if (existing != null) {
      await db.delete('lattice_prekeys', 'user_id', userId);
    }
    await db.insert('lattice_prekeys', {
      'user_id': userId,
      'bundle_data': _encodeBytes(bundleData),
      'uploaded_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns the serialized pre-key bundle for [userId], or `null` if none.
  Future<Uint8List?> getPreKey(String userId) async {
    final row = await db.findOne('lattice_prekeys', 'user_id', userId);
    if (row == null) return null;
    return _decodeBytes(row['bundle_data'] as String);
  }

  /// Removes the pre-key bundle for [userId].
  Future<void> removePreKey(String userId) async {
    await db.delete('lattice_prekeys', 'user_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Message operations
  // ---------------------------------------------------------------------------

  /// Stores a pending message from [senderId] to [recipientId].
  ///
  /// The [messageData] should be a serialized [KeyExchangeMessage].
  Future<void> storeMessage(
    String recipientId,
    String senderId,
    Uint8List messageData,
  ) async {
    await db.insert('lattice_messages', {
      'recipient_id': recipientId,
      'sender_id': senderId,
      'message_data': _encodeBytes(messageData),
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns all pending messages for [userId].
  Future<List<({String senderId, Uint8List messageData, String sentAt})>>
  getMessages(String userId) async {
    final rows = await db.findAll(
      'lattice_messages',
      whereKey: 'recipient_id',
      whereValue: userId,
    );
    return rows
        .map(
          (row) => (
            senderId: row['sender_id'] as String,
            messageData: _decodeBytes(row['message_data'] as String),
            sentAt: row['sent_at'] as String,
          ),
        )
        .toList();
  }

  /// Removes all pending messages for [userId].
  Future<void> clearMessages(String userId) async {
    await db.delete('lattice_messages', 'recipient_id', userId);
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  /// Returns the total number of registered users.
  Future<int> getUserCount() async => db.count('lattice_users');

  /// Returns the total number of stored pre-key bundles.
  Future<int> getPreKeyCount() async => db.count('lattice_prekeys');

  /// Returns the total number of pending messages.
  Future<int> getMessageCount() async => db.count('lattice_messages');

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _encodeBytes(Uint8List data) => base64Encode(data);
  static Uint8List _decodeBytes(String data) => base64Decode(data);
}
