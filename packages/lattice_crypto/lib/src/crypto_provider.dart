import 'package:lattice_crypto/src/ext.dart';
import 'package:lattice_crypto/src/kem.dart';
import 'package:lattice_crypto/src/kem_pure.dart';
import 'package:lattice_crypto/src/prf.dart';
import 'package:lattice_crypto/src/ring_sig.dart';
import 'package:lattice_crypto/src/ring_sig_pure.dart';
import 'package:lattice_crypto/src/security_level.dart';
import 'package:lattice_crypto/src/sig.dart';
import 'package:lattice_crypto/src/sig_pure.dart';

/// Factory for creating cryptographic primitive instances at a given
/// [SecurityLevel].
///
/// Currently returns pure-Dart development implementations. When native
/// FFI bindings for ML-KEM and ML-DSA become available, this class will
/// be updated to return production implementations.
class CryptoProvider {
  /// Creates a [CryptoProvider] for the given [level].
  ///
  /// Defaults to [SecurityLevel.l192] (NIST Level 3, 192-bit security).
  const CryptoProvider({this.level = SecurityLevel.l192});

  /// The security level used for all primitive instantiations.
  final SecurityLevel level;

  /// Returns a KEM instance for this security level.
  Kem get kem => KemPure(level);

  /// Returns a digital signature instance for this security level.
  Sig get sig => SigPure(level);

  /// Returns a ring signature instance for this security level.
  RingSig get ringSig => RingSigPure(level);

  /// Returns the PRF instance.
  Prf get prf => const Prf();

  /// Returns the randomness extractor instance.
  Ext get ext => const Ext();
}
