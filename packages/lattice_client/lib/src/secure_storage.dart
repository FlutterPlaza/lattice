import 'package:lattice_protocol/lattice_protocol.dart';

/// Abstract secure storage for cryptographic keys.
///
/// Implementations handle persistence of long-term identity keys and
/// ephemeral pre-keys. Production implementations should use platform-specific
/// secure storage (e.g. Keychain on iOS, Keystore on Android).
abstract class SecureStorage {
  /// Saves the long-term key pair for [userId].
  Future<void> saveIdentity(
    String userId,
    LongTermPublicKey publicKey,
    LongTermSecretKey secretKey,
  );

  /// Retrieves the long-term public key for [userId], or `null` if not found.
  Future<LongTermPublicKey?> getPublicKey(String userId);

  /// Retrieves the long-term secret key for [userId], or `null` if not found.
  Future<LongTermSecretKey?> getSecretKey(String userId);

  /// Saves an ephemeral pre-key for [userId].
  Future<void> savePreKey(String userId, EphemeralPreKey preKey);

  /// Retrieves the ephemeral pre-key for [userId], or `null` if not found.
  Future<EphemeralPreKey?> getPreKey(String userId);

  /// Removes the ephemeral pre-key for [userId].
  Future<void> removePreKey(String userId);

  /// Clears all stored keys.
  Future<void> clear();
}

/// In-memory implementation of [SecureStorage] for development and testing.
///
/// Keys are stored in plain Dart maps and are lost when the process exits.
/// Do **not** use in production.
class InMemorySecureStorage implements SecureStorage {
  final Map<String, LongTermPublicKey> _publicKeys =
      <String, LongTermPublicKey>{};
  final Map<String, LongTermSecretKey> _secretKeys =
      <String, LongTermSecretKey>{};
  final Map<String, EphemeralPreKey> _preKeys = <String, EphemeralPreKey>{};

  @override
  Future<void> saveIdentity(
    String userId,
    LongTermPublicKey publicKey,
    LongTermSecretKey secretKey,
  ) async {
    _publicKeys[userId] = publicKey;
    _secretKeys[userId] = secretKey;
  }

  @override
  Future<LongTermPublicKey?> getPublicKey(String userId) async {
    return _publicKeys[userId];
  }

  @override
  Future<LongTermSecretKey?> getSecretKey(String userId) async {
    return _secretKeys[userId];
  }

  @override
  Future<void> savePreKey(String userId, EphemeralPreKey preKey) async {
    _preKeys[userId] = preKey;
  }

  @override
  Future<EphemeralPreKey?> getPreKey(String userId) async {
    return _preKeys[userId];
  }

  @override
  Future<void> removePreKey(String userId) async {
    _preKeys.remove(userId);
  }

  @override
  Future<void> clear() async {
    _publicKeys.clear();
    _secretKeys.clear();
    _preKeys.clear();
  }
}
