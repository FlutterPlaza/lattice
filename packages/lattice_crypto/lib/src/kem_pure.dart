import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:lattice_crypto/src/kem.dart';
import 'package:lattice_crypto/src/security_level.dart';

/// Pure Dart development KEM implementation for protocol testing.
///
/// **WARNING**: This is NOT a cryptographically secure KEM. It is a
/// deterministic simulation that enables correct protocol-level testing
/// without requiring native ML-KEM (Kyber) bindings.
///
/// Construction:
/// - `keyGen()`: seed = 32 random bytes, pk = SHA-256(seed) padded to
///   [SecurityLevel.kemPublicKeySize], sk = seed || pk padded to
///   [SecurityLevel.kemSecretKeySize].
/// - `encap(pk)`: ephemeral = 32 random bytes,
///   ss = HMAC-SHA256(pk[0:32], ephemeral),
///   ct = ephemeral padded to [SecurityLevel.kemCiphertextSize].
/// - `decap(sk, ct)`: extract seed from sk, recompute pk = SHA-256(seed),
///   extract ephemeral from ct, ss = HMAC-SHA256(pk[0:32], ephemeral).
///
/// Encap and decap produce identical shared secrets because both use the
/// same pk-derived HMAC key and the same ephemeral value.
class KemPure implements Kem {
  /// Creates a [KemPure] for the given [level].
  const KemPure(this.level);

  @override
  final SecurityLevel level;

  /// The size of the internal seed in bytes.
  static const int _seedSize = 32;

  @override
  KemKeyPair keyGen() {
    final rng = Random.secure();
    final seed = Uint8List(_seedSize);
    for (var i = 0; i < _seedSize; i++) {
      seed[i] = rng.nextInt(256);
    }

    // pk = SHA-256(seed), padded to kemPublicKeySize
    final pkHash = sha256.convert(seed).bytes;
    final pk = Uint8List(level.kemPublicKeySize);
    pk.setRange(0, pkHash.length, pkHash);
    // Fill remaining bytes with a deterministic expansion
    _expandInto(pk, pkHash.length, seed, 0x10);

    // sk = seed || pk, padded to kemSecretKeySize
    final sk = Uint8List(level.kemSecretKeySize);
    sk.setRange(0, _seedSize, seed);
    sk.setRange(_seedSize, _seedSize + pk.length, pk);

    return KemKeyPair(publicKey: pk, secretKey: sk);
  }

  @override
  KemEncapsulation encap(Uint8List publicKey) {
    final rng = Random.secure();
    final ephemeral = Uint8List(_seedSize);
    for (var i = 0; i < _seedSize; i++) {
      ephemeral[i] = rng.nextInt(256);
    }

    // Shared secret = HMAC-SHA256(pk[0:32], ephemeral)
    final hmacKey = publicKey.sublist(0, _seedSize);
    final hmac = Hmac(sha256, hmacKey);
    final ss = Uint8List.fromList(hmac.convert(ephemeral).bytes);

    // Ciphertext = ephemeral, padded to kemCiphertextSize
    final ct = Uint8List(level.kemCiphertextSize);
    ct.setRange(0, _seedSize, ephemeral);

    return KemEncapsulation(ciphertext: ct, sharedSecret: ss);
  }

  @override
  Uint8List decap(Uint8List secretKey, Uint8List ciphertext) {
    // Extract seed from sk
    final seed = secretKey.sublist(0, _seedSize);

    // Recompute pk = SHA-256(seed)
    final pkHash = sha256.convert(seed).bytes;
    final hmacKey = Uint8List.fromList(pkHash);

    // Extract ephemeral from ciphertext
    final ephemeral = ciphertext.sublist(0, _seedSize);

    // Shared secret = HMAC-SHA256(pk[0:32], ephemeral)
    final hmac = Hmac(sha256, hmacKey);
    return Uint8List.fromList(hmac.convert(ephemeral).bytes);
  }

  /// Fills [buffer] starting at [offset] with deterministic bytes derived
  /// from [seed] using HMAC with the given [domainByte].
  static void _expandInto(
    Uint8List buffer,
    int offset,
    Uint8List seed,
    int domainByte,
  ) {
    if (offset >= buffer.length) return;

    final hmac = Hmac(sha256, seed);
    var counter = 0;
    var pos = offset;
    while (pos < buffer.length) {
      final block = hmac.convert([domainByte, counter]).bytes;
      final toCopy =
          (pos + block.length > buffer.length)
              ? buffer.length - pos
              : block.length;
      buffer.setRange(pos, pos + toCopy, block);
      pos += toCopy;
      counter++;
    }
  }
}
