import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// User record stored on the server.
///
/// Contains the user's identity and their serialized long-term public key.
class UserRecord {
  /// Creates a [UserRecord] with the given [userId] and [publicKeyData].
  UserRecord({
    required this.userId,
    required this.publicKeyData,
    DateTime? registeredAt,
  }) : registeredAt = registeredAt ?? DateTime.now();

  /// Creates a [UserRecord] from a JSON map.
  factory UserRecord.fromJson(Map<String, dynamic> json) => UserRecord(
    userId: json['userId'] as String,
    publicKeyData: base64Decode(json['publicKeyData'] as String),
    registeredAt: DateTime.parse(json['registeredAt'] as String),
  );

  /// The unique user identifier.
  final String userId;

  /// Serialized [LongTermPublicKey] bytes.
  final Uint8List publicKeyData;

  /// When the user was registered.
  final DateTime registeredAt;

  /// Converts this record to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'publicKeyData': base64Encode(publicKeyData),
    'registeredAt': registeredAt.toIso8601String(),
  };
}

/// Pre-key bundle record stored on the server.
class PreKeyRecord {
  /// Creates a [PreKeyRecord] with the given [userId] and [bundleData].
  PreKeyRecord({
    required this.userId,
    required this.bundleData,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  /// Creates a [PreKeyRecord] from a JSON map.
  factory PreKeyRecord.fromJson(Map<String, dynamic> json) => PreKeyRecord(
    userId: json['userId'] as String,
    bundleData: base64Decode(json['bundleData'] as String),
    uploadedAt: DateTime.parse(json['uploadedAt'] as String),
  );

  /// The user who uploaded this pre-key bundle.
  final String userId;

  /// Serialized [PreKeyBundle] bytes.
  final Uint8List bundleData;

  /// When the pre-key bundle was uploaded.
  final DateTime uploadedAt;

  /// Converts this record to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'bundleData': base64Encode(bundleData),
    'uploadedAt': uploadedAt.toIso8601String(),
  };
}

/// Pending message record stored on the server.
class MessageRecord {
  /// Creates a [MessageRecord] with the given fields.
  MessageRecord({
    required this.recipientId,
    required this.senderId,
    required this.messageData,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();

  /// Creates a [MessageRecord] from a JSON map.
  factory MessageRecord.fromJson(Map<String, dynamic> json) => MessageRecord(
    recipientId: json['recipientId'] as String,
    senderId: json['senderId'] as String,
    messageData: base64Decode(json['messageData'] as String),
    sentAt: DateTime.parse(json['sentAt'] as String),
  );

  /// The intended recipient of this message.
  final String recipientId;

  /// The sender of this message.
  final String senderId;

  /// Serialized [KeyExchangeMessage] bytes.
  final Uint8List messageData;

  /// When the message was sent.
  final DateTime sentAt;

  /// Converts this record to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'recipientId': recipientId,
    'senderId': senderId,
    'messageData': base64Encode(messageData),
    'sentAt': sentAt.toIso8601String(),
  };
}

/// Abstract storage interface for the Lattice key distribution server.
///
/// Implementations must support CRUD operations for users, pre-key bundles,
/// and pending key exchange messages.
abstract class Storage {
  // -- Users --

  /// Registers a new user. Throws [StateError] if the user already exists.
  Future<void> registerUser(UserRecord record);

  /// Returns the [UserRecord] for [userId], or `null` if not found.
  Future<UserRecord?> getUser(String userId);

  // -- Pre-keys --

  /// Stores (or replaces) a pre-key bundle for a user.
  Future<void> storePreKey(PreKeyRecord record);

  /// Returns the [PreKeyRecord] for [userId], or `null` if none available.
  Future<PreKeyRecord?> getPreKey(String userId);

  /// Removes the pre-key bundle for [userId].
  Future<void> removePreKey(String userId);

  // -- Messages --

  /// Stores a pending message for later retrieval.
  Future<void> storeMessage(MessageRecord record);

  /// Returns all pending messages for [userId].
  Future<List<MessageRecord>> getMessages(String userId);

  /// Removes all pending messages for [userId].
  Future<void> clearMessages(String userId);

  // -- Stats --

  /// Returns the total number of registered users.
  Future<int> getUserCount();

  /// Returns the total number of stored pre-key bundles.
  Future<int> getPreKeyCount();

  /// Returns the total number of pending messages.
  Future<int> getMessageCount();
}

/// In-memory storage backend for development and testing.
///
/// All data is lost when the process exits.
class InMemoryStorage implements Storage {
  final Map<String, UserRecord> _users = {};
  final Map<String, PreKeyRecord> _preKeys = {};
  final Map<String, List<MessageRecord>> _messages = {};

  @override
  Future<void> registerUser(UserRecord record) async {
    if (_users.containsKey(record.userId)) {
      throw StateError('User "${record.userId}" already registered');
    }
    _users[record.userId] = record;
  }

  @override
  Future<UserRecord?> getUser(String userId) async => _users[userId];

  @override
  Future<void> storePreKey(PreKeyRecord record) async {
    _preKeys[record.userId] = record;
  }

  @override
  Future<PreKeyRecord?> getPreKey(String userId) async => _preKeys[userId];

  @override
  Future<void> removePreKey(String userId) async {
    _preKeys.remove(userId);
  }

  @override
  Future<void> storeMessage(MessageRecord record) async {
    _messages.putIfAbsent(record.recipientId, () => []).add(record);
  }

  @override
  Future<List<MessageRecord>> getMessages(String userId) async =>
      List<MessageRecord>.from(_messages[userId] ?? []);

  @override
  Future<void> clearMessages(String userId) async {
    _messages.remove(userId);
  }

  @override
  Future<int> getUserCount() async => _users.length;

  @override
  Future<int> getPreKeyCount() async => _preKeys.length;

  @override
  Future<int> getMessageCount() async =>
      _messages.values.fold<int>(0, (sum, list) => sum + list.length);
}

/// File-based persistent storage backend.
///
/// Stores data as JSON files in the given [storagePath] directory.
/// Suitable for single-instance production deployments.
class FileStorage implements Storage {
  /// Creates a [FileStorage] that persists data under [storagePath].
  FileStorage(this.storagePath) {
    final dir = Directory(storagePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// The directory path where data files are stored.
  final String storagePath;

  String get _usersFile => '$storagePath/users.json';
  String get _preKeysFile => '$storagePath/prekeys.json';
  String get _messagesFile => '$storagePath/messages.json';

  Map<String, dynamic> _readJsonFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    if (content.isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  void _writeJsonFile(String path, Map<String, dynamic> data) {
    final file = File(path);
    file.writeAsStringSync(jsonEncode(data));
  }

  // -- Users --

  @override
  Future<void> registerUser(UserRecord record) async {
    final data = _readJsonFile(_usersFile);
    if (data.containsKey(record.userId)) {
      throw StateError('User "${record.userId}" already registered');
    }
    data[record.userId] = record.toJson();
    _writeJsonFile(_usersFile, data);
  }

  @override
  Future<UserRecord?> getUser(String userId) async {
    final data = _readJsonFile(_usersFile);
    final json = data[userId];
    if (json == null) return null;
    return UserRecord.fromJson(json as Map<String, dynamic>);
  }

  // -- Pre-keys --

  @override
  Future<void> storePreKey(PreKeyRecord record) async {
    final data = _readJsonFile(_preKeysFile);
    data[record.userId] = record.toJson();
    _writeJsonFile(_preKeysFile, data);
  }

  @override
  Future<PreKeyRecord?> getPreKey(String userId) async {
    final data = _readJsonFile(_preKeysFile);
    final json = data[userId];
    if (json == null) return null;
    return PreKeyRecord.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<void> removePreKey(String userId) async {
    final data = _readJsonFile(_preKeysFile);
    data.remove(userId);
    _writeJsonFile(_preKeysFile, data);
  }

  // -- Messages --

  @override
  Future<void> storeMessage(MessageRecord record) async {
    final data = _readJsonFile(_messagesFile);
    final key = record.recipientId;
    final existing = data[key] as List<dynamic>? ?? [];
    existing.add(record.toJson());
    data[key] = existing;
    _writeJsonFile(_messagesFile, data);
  }

  @override
  Future<List<MessageRecord>> getMessages(String userId) async {
    final data = _readJsonFile(_messagesFile);
    final list = data[userId] as List<dynamic>? ?? [];
    return list
        .map((e) => MessageRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> clearMessages(String userId) async {
    final data = _readJsonFile(_messagesFile);
    data.remove(userId);
    _writeJsonFile(_messagesFile, data);
  }

  // -- Stats --

  @override
  Future<int> getUserCount() async => _readJsonFile(_usersFile).length;

  @override
  Future<int> getPreKeyCount() async => _readJsonFile(_preKeysFile).length;

  @override
  Future<int> getMessageCount() async {
    final data = _readJsonFile(_messagesFile);
    var count = 0;
    for (final entry in data.values) {
      count += (entry as List<dynamic>).length;
    }
    return count;
  }
}
