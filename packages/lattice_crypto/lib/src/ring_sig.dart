import 'dart:typed_data';

import 'package:lattice_crypto/src/security_level.dart';
import 'package:lattice_crypto/src/sig.dart';

/// Abstract ring signature interface for SC-DAKE (Strongly Compromised
/// Deniable Authenticated Key Exchange).
///
/// A ring signature allows a signer to produce a signature that can be
/// verified as coming from one member of a set (ring) of public keys,
/// without revealing which member actually signed.
abstract class RingSig {
  /// The security level that determines parameter sizes.
  SecurityLevel get level;

  /// Generates a fresh key pair compatible with ring signing.
  SigKeyPair keyGen();

  /// Creates a ring signature over [message] using [signingKey] within the
  /// given [ring] of verification keys.
  ///
  /// The signer's verification key must be present in [ring].
  Uint8List ringSign(
    Uint8List signingKey,
    Uint8List message,
    List<Uint8List> ring,
  );

  /// Verifies that [signature] is a valid ring signature for [message]
  /// under the given [ring] of verification keys.
  ///
  /// Returns `true` if the signature is valid and the signer is a member
  /// of the ring, `false` otherwise.
  bool ringVerify(Uint8List message, Uint8List signature, List<Uint8List> ring);
}
