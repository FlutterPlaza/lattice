/// Security level selection for cryptographic operations.
///
/// Each level corresponds to a NIST post-quantum security category and
/// determines the parameter sizes for ML-KEM and ML-DSA instantiations.
enum SecurityLevel {
  /// NIST Level 1 (128-bit security) - ML-KEM-512, ML-DSA-44.
  l128(128, 'ML-KEM-512', 'ML-DSA-44', 800, 1632, 768, 1312, 2420),

  /// NIST Level 3 (192-bit security) - ML-KEM-768, ML-DSA-65.
  l192(192, 'ML-KEM-768', 'ML-DSA-65', 1184, 2400, 1088, 1952, 3309),

  /// NIST Level 5 (256-bit security) - ML-KEM-1024, ML-DSA-87.
  l256(256, 'ML-KEM-1024', 'ML-DSA-87', 1568, 3168, 1568, 2592, 4627);

  /// Creates a [SecurityLevel] with the given cryptographic parameters.
  const SecurityLevel(
    this.bits,
    this.kemName,
    this.sigName,
    this.kemPublicKeySize,
    this.kemSecretKeySize,
    this.kemCiphertextSize,
    this.sigPublicKeySize,
    this.sigSignatureSize,
  );

  /// The security strength in bits (128, 192, or 256).
  final int bits;

  /// The name of the KEM algorithm (e.g. 'ML-KEM-768').
  final String kemName;

  /// The name of the signature algorithm (e.g. 'ML-DSA-65').
  final String sigName;

  /// The size of a KEM public (encapsulation) key in bytes.
  final int kemPublicKeySize;

  /// The size of a KEM secret (decapsulation) key in bytes.
  final int kemSecretKeySize;

  /// The size of a KEM ciphertext in bytes.
  final int kemCiphertextSize;

  /// The size of a signature verification (public) key in bytes.
  final int sigPublicKeySize;

  /// The size of a signature in bytes.
  final int sigSignatureSize;

  /// Session key size in bytes (bits / 8).
  int get sessionKeySize => bits ~/ 8;

  /// PRF output size: session key + signature encryption OTP.
  int get prfOutputSize => sessionKeySize + sigSignatureSize;
}
