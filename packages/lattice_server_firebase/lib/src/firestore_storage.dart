import 'dart:convert';
import 'dart:typed_data';

/// Abstract adapter for Firestore operations.
///
/// Implementations may use the official Firestore SDK, the REST API, or an
/// in-memory fake for testing.
abstract class FirestoreAdapter {
  /// Sets (creates or overwrites) a document in [collection] with the given
  /// [documentId] and [data].
  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  );

  /// Returns the document data for [documentId] in [collection], or `null`
  /// if the document does not exist.
  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String documentId,
  );

  /// Returns all documents in [collection], optionally filtered by a
  /// field equality constraint.
  Future<List<Map<String, dynamic>>> getCollection(
    String collection, {
    String? whereField,
    String? whereValue,
  });

  /// Deletes the document with [documentId] from [collection].
  Future<void> deleteDocument(String collection, String documentId);

  /// Adds a new document to [collection] with an auto-generated ID.
  Future<void> addDocument(String collection, Map<String, dynamic> data);

  /// Returns the number of documents in [collection].
  Future<int> countDocuments(String collection);
}

/// Firestore-backed storage for the Lattice key distribution server.
///
/// Maps Lattice storage concepts (users, pre-keys, messages) to Firestore
/// collections via a [FirestoreAdapter].
class FirestoreStorage {
  /// Creates a [FirestoreStorage] backed by the given [firestore] adapter.
  const FirestoreStorage(this.firestore);

  /// The Firestore adapter used for all document operations.
  final FirestoreAdapter firestore;

  // -- Collection names -------------------------------------------------------

  static const String _usersCollection = 'lattice_users';
  static const String _preKeysCollection = 'lattice_prekeys';
  static const String _messagesCollection = 'lattice_messages';

  // -- Users ------------------------------------------------------------------

  /// Registers a new user with the given [userId] and [publicKeyData].
  ///
  /// Throws [StateError] if a user with [userId] is already registered.
  Future<void> registerUser(String userId, Uint8List publicKeyData) async {
    final existing = await firestore.getDocument(_usersCollection, userId);
    if (existing != null) {
      throw StateError('User "$userId" already registered');
    }
    await firestore.setDocument(_usersCollection, userId, {
      'public_key': base64Encode(publicKeyData),
      'registered_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns the public key bytes for [userId], or `null` if the user is not
  /// registered.
  Future<Uint8List?> getUserPublicKey(String userId) async {
    final doc = await firestore.getDocument(_usersCollection, userId);
    if (doc == null) return null;
    return base64Decode(doc['public_key'] as String);
  }

  // -- Pre-keys ---------------------------------------------------------------

  /// Stores (or replaces) a pre-key bundle for [userId].
  Future<void> storePreKey(String userId, Uint8List bundleData) async {
    await firestore.setDocument(_preKeysCollection, userId, {
      'bundle': base64Encode(bundleData),
      'uploaded_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns the pre-key bundle bytes for [userId], or `null` if none is
  /// available.
  Future<Uint8List?> getPreKey(String userId) async {
    final doc = await firestore.getDocument(_preKeysCollection, userId);
    if (doc == null) return null;
    return base64Decode(doc['bundle'] as String);
  }

  /// Removes the pre-key bundle for [userId].
  Future<void> removePreKey(String userId) async {
    await firestore.deleteDocument(_preKeysCollection, userId);
  }

  // -- Messages ---------------------------------------------------------------

  /// Stores a pending message from [senderId] to [recipientId].
  Future<void> storeMessage(
    String recipientId,
    String senderId,
    Uint8List messageData,
  ) async {
    await firestore.addDocument(_messagesCollection, {
      'recipient_id': recipientId,
      'sender_id': senderId,
      'message': base64Encode(messageData),
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns all pending messages for [userId] as a list of records.
  Future<List<({String senderId, Uint8List messageData})>> getMessages(
    String userId,
  ) async {
    final docs = await firestore.getCollection(
      _messagesCollection,
      whereField: 'recipient_id',
      whereValue: userId,
    );

    return docs.map((doc) {
      return (
        senderId: doc['sender_id'] as String,
        messageData: base64Decode(doc['message'] as String),
      );
    }).toList();
  }

  /// Removes all pending messages for [userId].
  Future<void> clearMessages(String userId) async {
    final docs = await firestore.getCollection(
      _messagesCollection,
      whereField: 'recipient_id',
      whereValue: userId,
    );

    for (final doc in docs) {
      final docId = doc['_id'] as String?;
      if (docId != null) {
        await firestore.deleteDocument(_messagesCollection, docId);
      }
    }
  }

  // -- Stats ------------------------------------------------------------------

  /// Returns the total number of registered users.
  Future<int> getUserCount() async =>
      firestore.countDocuments(_usersCollection);

  /// Returns the total number of stored pre-key bundles.
  Future<int> getPreKeyCount() async =>
      firestore.countDocuments(_preKeysCollection);

  /// Returns the total number of pending messages.
  Future<int> getMessageCount() async =>
      firestore.countDocuments(_messagesCollection);
}
