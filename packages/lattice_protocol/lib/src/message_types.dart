import 'dart:typed_data';

import 'package:lattice_protocol/src/key_types.dart';
import 'package:lattice_protocol/src/serialization.dart';

/// Pre-key bundle: `(lpk, ekT, sigma_A)` -- published to a server so that
/// Bob can initiate a session with Alice without her being online.
class PreKeyBundle {
  /// Creates a [PreKeyBundle] from the given components.
  const PreKeyBundle({
    required this.longTermPublicKey,
    required this.ephemeralPublicKey,
    required this.signature,
  });

  /// Deserializes a [PreKeyBundle] from its length-prefixed binary
  /// representation.
  factory PreKeyBundle.deserialize(Uint8List data) {
    var offset = 0;
    final (lpkBytes, lpkConsumed) = Serialization.readLengthPrefixed(
      data,
      offset,
    );
    offset += lpkConsumed;
    final (ekT, ekTConsumed) = Serialization.readLengthPrefixed(data, offset);
    offset += ekTConsumed;
    final (sigma, _) = Serialization.readLengthPrefixed(data, offset);
    return PreKeyBundle(
      longTermPublicKey: LongTermPublicKey.deserialize(lpkBytes),
      ephemeralPublicKey: ekT,
      signature: sigma,
    );
  }

  /// Alice's long-term public key `lpk_A`.
  final LongTermPublicKey longTermPublicKey;

  /// The ephemeral encapsulation key `ekT` (ek-tilde).
  final Uint8List ephemeralPublicKey;

  /// The signature `sigma_A = SIG.Sign(skA, ekT)`.
  final Uint8List signature;

  /// Serializes as a length-prefixed concatenation: `[lpk][ekT][sigma]`.
  Uint8List serialize() {
    final builder = BytesBuilder(copy: false);
    Serialization.writeLengthPrefixed(builder, longTermPublicKey.serialize());
    Serialization.writeLengthPrefixed(builder, ephemeralPublicKey);
    Serialization.writeLengthPrefixed(builder, signature);
    return builder.takeBytes();
  }
}

/// Key exchange message: `(C, CT, c)` -- sent from Bob to Alice.
///
/// `C` is the KEM ciphertext under Alice's long-term key, `CT` is the weak
/// KEM ciphertext under Alice's ephemeral key, and `c` is Bob's signature
/// encrypted with the one-time pad `k_tilde`.
class KeyExchangeMessage {
  /// Creates a [KeyExchangeMessage] from the given components.
  const KeyExchangeMessage({
    required this.ciphertext,
    required this.ephemeralCiphertext,
    required this.encryptedSignature,
  });

  /// Deserializes a [KeyExchangeMessage] from its length-prefixed binary
  /// representation.
  factory KeyExchangeMessage.deserialize(Uint8List data) {
    var offset = 0;
    final (c, cConsumed) = Serialization.readLengthPrefixed(data, offset);
    offset += cConsumed;
    final (ct, ctConsumed) = Serialization.readLengthPrefixed(data, offset);
    offset += ctConsumed;
    final (enc, _) = Serialization.readLengthPrefixed(data, offset);
    return KeyExchangeMessage(
      ciphertext: c,
      ephemeralCiphertext: ct,
      encryptedSignature: enc,
    );
  }

  /// The KEM ciphertext `C`.
  final Uint8List ciphertext;

  /// The weak KEM ciphertext `CT` (C-tilde).
  final Uint8List ephemeralCiphertext;

  /// The encrypted signature `c = sigma XOR k_tilde`.
  final Uint8List encryptedSignature;

  /// Serializes as a length-prefixed concatenation: `[C][CT][c]`.
  Uint8List serialize() {
    final builder = BytesBuilder(copy: false);
    Serialization.writeLengthPrefixed(builder, ciphertext);
    Serialization.writeLengthPrefixed(builder, ephemeralCiphertext);
    Serialization.writeLengthPrefixed(builder, encryptedSignature);
    return builder.takeBytes();
  }
}
