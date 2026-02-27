import 'dart:typed_data';

import 'package:lattice_crypto/src/security_level.dart';

/// A KEM key pair consisting of a public (encapsulation) key and a secret
/// (decapsulation) key.
class KemKeyPair {
  /// Creates a [KemKeyPair] from the given [publicKey] and [secretKey].
  const KemKeyPair({required this.publicKey, required this.secretKey});

  /// The public (encapsulation) key.
  final Uint8List publicKey;

  /// The secret (decapsulation) key.
  final Uint8List secretKey;
}

/// The result of a KEM encapsulation: a [ciphertext] and a [sharedSecret].
class KemEncapsulation {
  /// Creates a [KemEncapsulation] from the given [ciphertext] and
  /// [sharedSecret].
  const KemEncapsulation({
    required this.ciphertext,
    required this.sharedSecret,
  });

  /// The ciphertext to be sent to the decapsulator.
  final Uint8List ciphertext;

  /// The shared secret produced by encapsulation.
  final Uint8List sharedSecret;
}

/// Abstract Key Encapsulation Mechanism (KEM) interface.
///
/// Implementations provide IND-CCA2 key encapsulation, such as ML-KEM
/// (CRYSTALS-Kyber).
abstract class Kem {
  /// The security level that determines parameter sizes.
  SecurityLevel get level;

  /// Generates a fresh KEM key pair.
  KemKeyPair keyGen();

  /// Encapsulates a shared secret under the given [publicKey].
  ///
  /// Returns a [KemEncapsulation] containing the ciphertext and the shared
  /// secret.
  KemEncapsulation encap(Uint8List publicKey);

  /// Decapsulates a shared secret from [ciphertext] using [secretKey].
  ///
  /// Returns the shared secret as a [Uint8List].
  Uint8List decap(Uint8List secretKey, Uint8List ciphertext);
}
