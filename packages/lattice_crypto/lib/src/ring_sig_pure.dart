import 'dart:typed_data';

import 'package:lattice_crypto/src/ring_sig.dart';
import 'package:lattice_crypto/src/security_level.dart';
import 'package:lattice_crypto/src/sig.dart';
import 'package:lattice_crypto/src/sig_pure.dart';

/// Pure Dart development ring signature implementation for protocol testing.
///
/// **WARNING**: This is NOT a cryptographically secure ring signature. It is
/// a simulation that enables correct protocol-level testing. The actual
/// signer is identifiable from the signature, which defeats the anonymity
/// property of real ring signatures.
///
/// Construction:
/// - `keyGen()`: delegates to [SigPure.keyGen].
/// - `ringSign(sk, msg, ring)`: creates a standard [SigPure] signature,
///   finds the signer's index in the ring by deriving the verification key
///   from the seed, and encodes (index, innerSignature) into the output.
/// - `ringVerify(msg, sig, ring)`: extracts the index, retrieves the
///   claimed verification key from the ring, and delegates to
///   [SigPure.verify].
///
/// Signature format: `[index (1 byte)] || [innerSignature]`
class RingSigPure implements RingSig {
  /// Creates a [RingSigPure] for the given [level].
  const RingSigPure(this.level);

  @override
  final SecurityLevel level;

  /// The underlying signature scheme used for inner signatures.
  SigPure get _sig => SigPure(level);

  /// The size of the ring index header in the signature.
  static const int _indexHeaderSize = 1;

  @override
  SigKeyPair keyGen() => _sig.keyGen();

  @override
  Uint8List ringSign(
    Uint8List signingKey,
    Uint8List message,
    List<Uint8List> ring,
  ) {
    if (ring.isEmpty) {
      throw ArgumentError('ring must not be empty');
    }
    if (ring.length > 255) {
      throw ArgumentError('ring must have at most 255 members');
    }

    // Derive the signer's verification key to find their index in the ring
    final seed = signingKey.sublist(0, SigPure.seedSize);
    final signerVk = _sig.deriveVerificationKey(seed);

    // Find the signer's index in the ring
    var signerIndex = -1;
    for (var i = 0; i < ring.length; i++) {
      if (_prefixEquals(ring[i], signerVk, SigPure.seedSize)) {
        signerIndex = i;
        break;
      }
    }
    if (signerIndex < 0) {
      throw ArgumentError('signer verification key not found in ring');
    }

    // Create the inner signature
    final innerSig = _sig.sign(signingKey, message);

    // Encode: [index] || [innerSignature]
    final output = Uint8List(_indexHeaderSize + innerSig.length);
    output[0] = signerIndex;
    output.setRange(_indexHeaderSize, output.length, innerSig);

    return output;
  }

  @override
  bool ringVerify(
    Uint8List message,
    Uint8List signature,
    List<Uint8List> ring,
  ) {
    if (signature.length < _indexHeaderSize + level.sigSignatureSize) {
      return false;
    }
    if (ring.isEmpty || ring.length > 255) {
      return false;
    }

    // Extract the claimed signer index
    final signerIndex = signature[0];
    if (signerIndex >= ring.length) {
      return false;
    }

    // Extract the inner signature
    final innerSig = signature.sublist(
      _indexHeaderSize,
      _indexHeaderSize + level.sigSignatureSize,
    );

    // Verify using the claimed ring member's verification key
    final vk = ring[signerIndex];
    return _sig.verify(vk, message, innerSig);
  }

  /// Compares the first [length] bytes of [a] and [b].
  static bool _prefixEquals(List<int> a, List<int> b, int length) {
    if (a.length < length || b.length < length) return false;
    var result = 0;
    for (var i = 0; i < length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
