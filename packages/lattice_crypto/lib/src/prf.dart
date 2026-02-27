import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pseudorandom function F_K(sid) with counter-mode extension.
///
/// Uses HMAC-SHA256 with a domain separator byte (0x01) and an HKDF-Expand
/// style counter mode to produce arbitrary-length output:
///
/// ```
/// T(1) = HMAC(key, 0x01 || sid || 0x01)
/// T(i) = HMAC(key, T(i-1) || 0x01 || sid || i)
/// output = T(1) || T(2) || ... truncated to outputLength
/// ```
///
/// This construction is used in the Signal PQC handshake protocol
/// (Hashimoto et al. PQC 2022) to derive session keys and one-time pads
/// for signature encryption.
class Prf {
  /// Creates a [Prf] instance.
  const Prf();

  /// Domain separator byte used in PRF evaluations.
  static const int _domainSeparator = 0x01;

  /// Evaluates the PRF on [key] and [sessionId], producing [outputLength]
  /// bytes of pseudorandom output.
  ///
  /// Uses HMAC-SHA256 in counter mode (HKDF-Expand style) to generate
  /// output longer than 32 bytes when needed.
  ///
  /// Throws [ArgumentError] if [outputLength] is non-positive or exceeds
  /// the maximum safe expansion length (255 * 32 = 8160 bytes).
  Uint8List evaluate(Uint8List key, Uint8List sessionId, int outputLength) {
    if (outputLength <= 0) {
      throw ArgumentError.value(
        outputLength,
        'outputLength',
        'must be positive',
      );
    }
    if (outputLength > 255 * 32) {
      throw ArgumentError.value(
        outputLength,
        'outputLength',
        'exceeds maximum safe expansion length (8160 bytes)',
      );
    }

    final hmac = Hmac(sha256, key);
    final result = BytesBuilder(copy: false);
    Uint8List previous = Uint8List(0);

    for (var counter = 1; result.length < outputLength; counter++) {
      // T(i) = HMAC(key, T(i-1) || 0x01 || sid || counter)
      final input =
          BytesBuilder(copy: false)
            ..add(previous)
            ..addByte(_domainSeparator)
            ..add(sessionId)
            ..addByte(counter);

      final digest = hmac.convert(input.takeBytes());
      previous = Uint8List.fromList(digest.bytes);
      result.add(previous);
    }

    final fullOutput = result.takeBytes();
    return Uint8List.fromList(fullOutput.sublist(0, outputLength));
  }
}
