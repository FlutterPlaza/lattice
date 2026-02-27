import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:lattice_crypto/src/security_level.dart';
import 'package:lattice_crypto/src/sig.dart';

/// Pure Dart development signature implementation for protocol testing.
///
/// **WARNING**: This is NOT a cryptographically secure signature scheme.
/// It is a simulation that enables correct protocol-level testing without
/// requiring native ML-DSA (Dilithium) bindings. The signing seed is
/// embedded in the signature, making it trivially forgeable.
///
/// Construction:
/// - `keyGen()`: seed = 32 random bytes,
///   vk = HMAC-SHA256(seed, 'vk_derive') expanded to
///   [SecurityLevel.sigPublicKeySize],
///   sk = seed padded to full signing key size.
/// - `sign(sk, msg)`: extract seed, core = HMAC-SHA256(seed, msg),
///   signature = seed || core, padded to [SecurityLevel.sigSignatureSize].
/// - `verify(vk, msg, sig)`: extract seed and core from sig,
///   check HMAC-SHA256(seed, msg) == core AND
///   HMAC-SHA256(seed, 'vk_derive')[0:32] == vk[0:32].
class SigPure implements Sig {
  /// Creates a [SigPure] for the given [level].
  const SigPure(this.level);

  @override
  final SecurityLevel level;

  /// The size of the internal seed in bytes.
  static const int seedSize = 32;

  /// The size of the HMAC tag in bytes.
  static const int _tagSize = 32;

  /// The derivation label for verification keys.
  static final Uint8List _vkLabel = Uint8List.fromList('vk_derive'.codeUnits);

  @override
  SigKeyPair keyGen() {
    final rng = Random.secure();
    final seed = Uint8List(seedSize);
    for (var i = 0; i < seedSize; i++) {
      seed[i] = rng.nextInt(256);
    }

    final vk = deriveVerificationKey(seed);
    final sk = Uint8List(
      level.kemSecretKeySize > seedSize ? level.kemSecretKeySize : seedSize,
    );
    // Store seed as the signing key (padded)
    sk.setRange(0, seedSize, seed);

    return SigKeyPair(verificationKey: vk, signingKey: sk);
  }

  @override
  Uint8List sign(Uint8List signingKey, Uint8List message) {
    final seed = signingKey.sublist(0, seedSize);

    // core = HMAC-SHA256(seed, message)
    final hmac = Hmac(sha256, seed);
    final core = Uint8List.fromList(hmac.convert(message).bytes);

    // signature = seed || core, padded to sigSignatureSize
    final sig = Uint8List(level.sigSignatureSize);
    sig.setRange(0, seedSize, seed);
    sig.setRange(seedSize, seedSize + _tagSize, core);

    return sig;
  }

  @override
  bool verify(
    Uint8List verificationKey,
    Uint8List message,
    Uint8List signature,
  ) {
    if (signature.length != level.sigSignatureSize) {
      return false;
    }

    // Extract seed and core from signature
    final seed = signature.sublist(0, seedSize);
    final core = signature.sublist(seedSize, seedSize + _tagSize);

    // Check that the HMAC tag matches
    final hmac = Hmac(sha256, seed);
    final expected = hmac.convert(message).bytes;
    if (!_constantTimeEquals(core, Uint8List.fromList(expected))) {
      return false;
    }

    // Check that the seed corresponds to the verification key
    final derivedVk = deriveVerificationKey(seed);
    return _constantTimeEquals(
      verificationKey.sublist(0, seedSize),
      derivedVk.sublist(0, seedSize),
    );
  }

  /// Derives a verification key from [seed].
  Uint8List deriveVerificationKey(Uint8List seed) {
    final hmac = Hmac(sha256, seed);
    final vkCore = hmac.convert(_vkLabel).bytes;

    final vk = Uint8List(level.sigPublicKeySize);
    vk.setRange(0, vkCore.length, vkCore);
    // Expand remaining bytes deterministically
    _expandInto(vk, vkCore.length, seed, 0x20);
    return vk;
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

  /// Constant-time comparison of two byte sequences.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
