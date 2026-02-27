import 'dart:typed_data';

import 'package:lattice_protocol/src/serialization.dart';

/// Long-term public key: `(ek, vk)` -- KEM encapsulation key + SIG
/// verification key.
///
/// In the protocol, this is denoted `lpk = (ek, vk)`.
class LongTermPublicKey {
  /// Creates a [LongTermPublicKey] from the given components.
  const LongTermPublicKey({
    required this.encapsulationKey,
    required this.verificationKey,
  });

  /// Deserializes a [LongTermPublicKey] from its length-prefixed binary
  /// representation.
  factory LongTermPublicKey.deserialize(Uint8List data) {
    var offset = 0;
    final (ek, ekConsumed) = Serialization.readLengthPrefixed(data, offset);
    offset += ekConsumed;
    final (vk, _) = Serialization.readLengthPrefixed(data, offset);
    return LongTermPublicKey(encapsulationKey: ek, verificationKey: vk);
  }

  /// The KEM encapsulation (public) key `ek`.
  final Uint8List encapsulationKey;

  /// The SIG verification (public) key `vk`.
  final Uint8List verificationKey;

  /// Serializes as a length-prefixed concatenation: `[ek][vk]`.
  Uint8List serialize() {
    final builder = BytesBuilder(copy: false);
    Serialization.writeLengthPrefixed(builder, encapsulationKey);
    Serialization.writeLengthPrefixed(builder, verificationKey);
    return builder.takeBytes();
  }
}

/// Long-term secret key: `(dk, sk)` -- KEM decapsulation key + SIG signing
/// key.
///
/// In the protocol, this is denoted `lsk = (dk, sk)`.
class LongTermSecretKey {
  /// Creates a [LongTermSecretKey] from the given components.
  const LongTermSecretKey({
    required this.decapsulationKey,
    required this.signingKey,
  });

  /// The KEM decapsulation (secret) key `dk`.
  final Uint8List decapsulationKey;

  /// The SIG signing (secret) key `sk`.
  final Uint8List signingKey;
}

/// Ephemeral pre-key: `(ekT, dkT, sigma)` -- weak KEM keypair + signature
/// on `ekT`.
///
/// `ekT` is the ephemeral encapsulation key (ek-tilde), `dkT` is its
/// corresponding decapsulation key (dk-tilde), and `sigma` is
/// `SIG.Sign(skA, ekT)`.
class EphemeralPreKey {
  /// Creates an [EphemeralPreKey] from the given components.
  const EphemeralPreKey({
    required this.ephemeralPublicKey,
    required this.ephemeralSecretKey,
    required this.signature,
  });

  /// The ephemeral encapsulation key `ekT` (ek-tilde).
  final Uint8List ephemeralPublicKey;

  /// The ephemeral decapsulation key `dkT` (dk-tilde).
  final Uint8List ephemeralSecretKey;

  /// The signature `sigma_A = SIG.Sign(skA, ekT)`.
  final Uint8List signature;
}

/// Session identifier built as a length-prefixed concatenation:
/// `A || B || lpkA || lpkB || ekT || C || CT`.
///
/// Each component is encoded with a 4-byte big-endian length prefix to
/// prevent ambiguity.
class SessionId {
  /// Creates a [SessionId] wrapping the given raw [data].
  const SessionId(this.data);

  /// Builds a session ID from its protocol components using length-prefixed
  /// encoding.
  factory SessionId.build({
    required String identityA,
    required String identityB,
    required LongTermPublicKey lpkA,
    required LongTermPublicKey lpkB,
    required Uint8List ephemeralPublicKey,
    required Uint8List ciphertext,
    required Uint8List ephemeralCiphertext,
  }) {
    final builder = BytesBuilder(copy: false);
    Serialization.writeLengthPrefixedString(builder, identityA);
    Serialization.writeLengthPrefixedString(builder, identityB);
    Serialization.writeLengthPrefixed(builder, lpkA.serialize());
    Serialization.writeLengthPrefixed(builder, lpkB.serialize());
    Serialization.writeLengthPrefixed(builder, ephemeralPublicKey);
    Serialization.writeLengthPrefixed(builder, ciphertext);
    Serialization.writeLengthPrefixed(builder, ephemeralCiphertext);
    return SessionId(builder.takeBytes());
  }

  /// The raw bytes of the session identifier.
  final Uint8List data;
}
