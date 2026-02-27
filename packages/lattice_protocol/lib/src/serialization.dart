import 'dart:convert';
import 'dart:typed_data';

/// Binary serialization helpers using length-prefixed encoding.
///
/// All multi-byte integers are encoded in big-endian (network) byte order.
/// Each field is written as a 4-byte length prefix followed by the raw bytes.
class Serialization {
  /// Writes a length-prefixed byte array to [builder].
  ///
  /// Format: `[4 bytes: big-endian length][data bytes]`.
  static void writeLengthPrefixed(BytesBuilder builder, Uint8List data) {
    final len = data.length;
    builder.addByte((len >> 24) & 0xFF);
    builder.addByte((len >> 16) & 0xFF);
    builder.addByte((len >> 8) & 0xFF);
    builder.addByte(len & 0xFF);
    builder.add(data);
  }

  /// Reads a length-prefixed byte array from [data] starting at [offset].
  ///
  /// Returns a record of `(bytes, bytesConsumed)` where `bytesConsumed`
  /// includes the 4-byte length prefix.
  ///
  /// Throws [RangeError] if there are not enough bytes to read.
  static (Uint8List, int) readLengthPrefixed(Uint8List data, int offset) {
    if (offset + 4 > data.length) {
      throw RangeError('Not enough bytes for length prefix at offset $offset');
    }
    final len =
        (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    if (offset + 4 + len > data.length) {
      throw RangeError(
        'Not enough bytes for payload of length $len at offset ${offset + 4}',
      );
    }
    final payload = Uint8List.sublistView(data, offset + 4, offset + 4 + len);
    return (Uint8List.fromList(payload), 4 + len);
  }

  /// Writes a length-prefixed UTF-8 string to [builder].
  ///
  /// The string is first encoded as UTF-8, then written with a 4-byte
  /// big-endian length prefix.
  static void writeLengthPrefixedString(BytesBuilder builder, String str) {
    final bytes = Uint8List.fromList(utf8.encode(str));
    writeLengthPrefixed(builder, bytes);
  }

  /// Reads a length-prefixed UTF-8 string from [data] starting at [offset].
  ///
  /// Returns a record of `(string, bytesConsumed)`.
  static (String, int) readLengthPrefixedString(Uint8List data, int offset) {
    final (bytes, consumed) = readLengthPrefixed(data, offset);
    return (utf8.decode(bytes), consumed);
  }
}
