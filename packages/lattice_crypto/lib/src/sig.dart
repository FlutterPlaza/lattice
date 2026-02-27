import 'dart:typed_data';

import 'package:lattice_crypto/src/security_level.dart';

/// A signature key pair consisting of a verification (public) key and a
/// signing (secret) key.
class SigKeyPair {
  /// Creates a [SigKeyPair] from the given [verificationKey] and
  /// [signingKey].
  const SigKeyPair({required this.verificationKey, required this.signingKey});

  /// The verification (public) key used to verify signatures.
  final Uint8List verificationKey;

  /// The signing (secret) key used to create signatures.
  final Uint8List signingKey;
}

/// Abstract digital signature interface.
///
/// Implementations provide EUF-CMA digital signatures, such as ML-DSA
/// (CRYSTALS-Dilithium).
abstract class Sig {
  /// The security level that determines parameter sizes.
  SecurityLevel get level;

  /// Generates a fresh signature key pair.
  SigKeyPair keyGen();

  /// Signs [message] using [signingKey].
  ///
  /// Returns the signature as a [Uint8List].
  Uint8List sign(Uint8List signingKey, Uint8List message);

  /// Verifies that [signature] is valid for [message] under
  /// [verificationKey].
  ///
  /// Returns `true` if the signature is valid, `false` otherwise.
  bool verify(
    Uint8List verificationKey,
    Uint8List message,
    Uint8List signature,
  );
}
