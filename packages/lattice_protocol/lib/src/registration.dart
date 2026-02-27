import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/src/key_types.dart';

/// The result of user registration: a long-term public/secret key pair.
class RegistrationResult {
  /// Creates a [RegistrationResult] from the given key pair.
  const RegistrationResult({required this.publicKey, required this.secretKey});

  /// The long-term public key `lpk = (ek, vk)`.
  final LongTermPublicKey publicKey;

  /// The long-term secret key `lsk = (dk, sk)`.
  final LongTermSecretKey secretKey;
}

/// User registration: generates a long-term key pair for use in the SC-AKE
/// protocol.
///
/// The key pair consists of KEM keys (for key encapsulation) and SIG keys
/// (for signing).
class Registration {
  /// Creates a [Registration] handler using the given [crypto] provider.
  const Registration(this.crypto);

  /// The cryptographic provider supplying KEM and SIG primitives.
  final CryptoProvider crypto;

  /// Generates a long-term key pair: `KEM.KeyGen + SIG.KeyGen -> (lpk, lsk)`.
  ///
  /// Returns a [RegistrationResult] containing the public and secret keys.
  RegistrationResult generate() {
    final kemKp = crypto.kem.keyGen();
    final sigKp = crypto.sig.keyGen();
    return RegistrationResult(
      publicKey: LongTermPublicKey(
        encapsulationKey: kemKp.publicKey,
        verificationKey: sigKp.verificationKey,
      ),
      secretKey: LongTermSecretKey(
        decapsulationKey: kemKp.secretKey,
        signingKey: sigKp.signingKey,
      ),
    );
  }
}
