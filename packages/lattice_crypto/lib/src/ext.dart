import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Strong randomness extractor Ext_s(K).
///
/// Computes:
/// ```
/// Ext_s(K) = HMAC-SHA256(s, 0x02 || K)
/// ```
///
/// where `s` is a 32-byte seed and `K` is the input keying material.
///
/// This is used in the Signal PQC handshake protocol (Hashimoto et al.
/// PQC 2022) to extract uniformly random keys from KEM shared secrets.
class Ext {
  /// Creates an [Ext] instance.
  const Ext();

  /// Domain separator byte used in extraction.
  static const int _domainSeparator = 0x02;

  /// Extracts a 32-byte uniform key from [input] using [seed] as the
  /// extraction key.
  ///
  /// The [seed] should be a 32-byte random value.
  /// Returns a 32-byte [Uint8List] containing the extracted key.
  ///
  /// Throws [ArgumentError] if [seed] is not exactly 32 bytes.
  Uint8List extract(Uint8List seed, Uint8List input) {
    if (seed.length != 32) {
      throw ArgumentError.value(
        seed.length,
        'seed.length',
        'seed must be exactly 32 bytes',
      );
    }

    final hmac = Hmac(sha256, seed);

    // Construct 0x02 || input
    final data = Uint8List(1 + input.length);
    data[0] = _domainSeparator;
    data.setRange(1, data.length, input);

    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }
}
