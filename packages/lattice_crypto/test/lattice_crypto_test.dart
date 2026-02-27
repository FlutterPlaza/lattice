import 'dart:typed_data';

import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('SecurityLevel', () {
    test('l128 has correct parameters', () {
      const level = SecurityLevel.l128;
      expect(level.bits, 128);
      expect(level.kemName, 'ML-KEM-512');
      expect(level.sigName, 'ML-DSA-44');
      expect(level.kemPublicKeySize, 800);
      expect(level.kemSecretKeySize, 1632);
      expect(level.kemCiphertextSize, 768);
      expect(level.sigPublicKeySize, 1312);
      expect(level.sigSignatureSize, 2420);
      expect(level.sessionKeySize, 16);
      expect(level.prfOutputSize, 16 + 2420);
    });

    test('l192 has correct parameters', () {
      const level = SecurityLevel.l192;
      expect(level.bits, 192);
      expect(level.kemName, 'ML-KEM-768');
      expect(level.sigName, 'ML-DSA-65');
      expect(level.kemPublicKeySize, 1184);
      expect(level.kemSecretKeySize, 2400);
      expect(level.kemCiphertextSize, 1088);
      expect(level.sigPublicKeySize, 1952);
      expect(level.sigSignatureSize, 3309);
      expect(level.sessionKeySize, 24);
      expect(level.prfOutputSize, 24 + 3309);
    });

    test('l256 has correct parameters', () {
      const level = SecurityLevel.l256;
      expect(level.bits, 256);
      expect(level.kemName, 'ML-KEM-1024');
      expect(level.sigName, 'ML-DSA-87');
      expect(level.kemPublicKeySize, 1568);
      expect(level.kemSecretKeySize, 3168);
      expect(level.kemCiphertextSize, 1568);
      expect(level.sigPublicKeySize, 2592);
      expect(level.sigSignatureSize, 4627);
      expect(level.sessionKeySize, 32);
      expect(level.prfOutputSize, 32 + 4627);
    });
  });

  for (final level in SecurityLevel.values) {
    group('KemPure (${level.name})', () {
      final kem = KemPure(level);

      test('keyGen produces correct key sizes', () {
        final kp = kem.keyGen();
        expect(kp.publicKey.length, level.kemPublicKeySize);
        expect(kp.secretKey.length, level.kemSecretKeySize);
      });

      test('encap produces correct sizes', () {
        final kp = kem.keyGen();
        final enc = kem.encap(kp.publicKey);
        expect(enc.ciphertext.length, level.kemCiphertextSize);
        expect(enc.sharedSecret.length, 32);
      });

      test('round-trip: encap then decap produces same shared secret', () {
        final kp = kem.keyGen();
        final enc = kem.encap(kp.publicKey);
        final ss = kem.decap(kp.secretKey, enc.ciphertext);
        expect(ss, equals(enc.sharedSecret));
      });

      test('different encapsulations produce different shared secrets', () {
        final kp = kem.keyGen();
        final enc1 = kem.encap(kp.publicKey);
        final enc2 = kem.encap(kp.publicKey);
        // Overwhelmingly likely to differ due to random ephemeral
        expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
      });

      test('decap with wrong secret key produces different shared secret', () {
        final kp1 = kem.keyGen();
        final kp2 = kem.keyGen();
        final enc = kem.encap(kp1.publicKey);
        final wrongSs = kem.decap(kp2.secretKey, enc.ciphertext);
        expect(wrongSs, isNot(equals(enc.sharedSecret)));
      });
    });

    group('SigPure (${level.name})', () {
      final sig = SigPure(level);

      test('keyGen produces correct key sizes', () {
        final kp = sig.keyGen();
        expect(kp.verificationKey.length, level.sigPublicKeySize);
        // signingKey is at least 32 bytes
        expect(kp.signingKey.length, greaterThanOrEqualTo(32));
      });

      test('sign produces correct signature size', () {
        final kp = sig.keyGen();
        final message = Uint8List.fromList('hello world'.codeUnits);
        final signature = sig.sign(kp.signingKey, message);
        expect(signature.length, level.sigSignatureSize);
      });

      test('round-trip: sign then verify returns true', () {
        final kp = sig.keyGen();
        final message = Uint8List.fromList('test message'.codeUnits);
        final signature = sig.sign(kp.signingKey, message);
        expect(sig.verify(kp.verificationKey, message, signature), isTrue);
      });

      test('verify rejects tampered message', () {
        final kp = sig.keyGen();
        final message = Uint8List.fromList('original'.codeUnits);
        final signature = sig.sign(kp.signingKey, message);
        final tampered = Uint8List.fromList('tampered'.codeUnits);
        expect(sig.verify(kp.verificationKey, tampered, signature), isFalse);
      });

      test('verify rejects wrong verification key', () {
        final kp1 = sig.keyGen();
        final kp2 = sig.keyGen();
        final message = Uint8List.fromList('test'.codeUnits);
        final signature = sig.sign(kp1.signingKey, message);
        expect(sig.verify(kp2.verificationKey, message, signature), isFalse);
      });

      test('verify rejects truncated signature', () {
        final kp = sig.keyGen();
        final message = Uint8List.fromList('test'.codeUnits);
        final signature = sig.sign(kp.signingKey, message);
        final truncated = signature.sublist(0, signature.length - 1);
        expect(sig.verify(kp.verificationKey, message, truncated), isFalse);
      });

      test('sign is deterministic for same key and message', () {
        final kp = sig.keyGen();
        final message = Uint8List.fromList('deterministic'.codeUnits);
        final sig1 = sig.sign(kp.signingKey, message);
        final sig2 = sig.sign(kp.signingKey, message);
        expect(sig1, equals(sig2));
      });
    });

    group('RingSigPure (${level.name})', () {
      final ringSig = RingSigPure(level);

      test('keyGen produces valid key pair', () {
        final kp = ringSig.keyGen();
        expect(kp.verificationKey.length, level.sigPublicKeySize);
        expect(kp.signingKey.length, greaterThanOrEqualTo(32));
      });

      test('ring sign and verify with ring of 2 keys', () {
        final kp1 = ringSig.keyGen();
        final kp2 = ringSig.keyGen();
        final ring = <Uint8List>[kp1.verificationKey, kp2.verificationKey];
        final message = Uint8List.fromList('ring message'.codeUnits);

        final signature = ringSig.ringSign(kp1.signingKey, message, ring);
        expect(ringSig.ringVerify(message, signature, ring), isTrue);
      });

      test('ring sign and verify with ring of 3 keys', () {
        final kp1 = ringSig.keyGen();
        final kp2 = ringSig.keyGen();
        final kp3 = ringSig.keyGen();
        final ring = <Uint8List>[
          kp1.verificationKey,
          kp2.verificationKey,
          kp3.verificationKey,
        ];
        final message = Uint8List.fromList('three members'.codeUnits);

        // Sign with the second member
        final signature = ringSig.ringSign(kp2.signingKey, message, ring);
        expect(ringSig.ringVerify(message, signature, ring), isTrue);
      });

      test('ring verify fails with wrong ring', () {
        final kp1 = ringSig.keyGen();
        final kp2 = ringSig.keyGen();
        final kp3 = ringSig.keyGen();
        final ring = <Uint8List>[kp1.verificationKey, kp2.verificationKey];
        final wrongRing = <Uint8List>[kp2.verificationKey, kp3.verificationKey];
        final message = Uint8List.fromList('wrong ring'.codeUnits);

        final signature = ringSig.ringSign(kp1.signingKey, message, ring);
        expect(ringSig.ringVerify(message, signature, wrongRing), isFalse);
      });

      test('ring verify fails with tampered message', () {
        final kp1 = ringSig.keyGen();
        final kp2 = ringSig.keyGen();
        final ring = <Uint8List>[kp1.verificationKey, kp2.verificationKey];
        final message = Uint8List.fromList('original'.codeUnits);

        final signature = ringSig.ringSign(kp1.signingKey, message, ring);
        final tampered = Uint8List.fromList('tampered'.codeUnits);
        expect(ringSig.ringVerify(tampered, signature, ring), isFalse);
      });

      test('ring sign throws when signer not in ring', () {
        final kp1 = ringSig.keyGen();
        final kp2 = ringSig.keyGen();
        final kp3 = ringSig.keyGen();
        final ring = <Uint8List>[kp1.verificationKey, kp2.verificationKey];
        final message = Uint8List.fromList('not in ring'.codeUnits);

        expect(
          () => ringSig.ringSign(kp3.signingKey, message, ring),
          throwsArgumentError,
        );
      });

      test('ring sign throws on empty ring', () {
        final kp = ringSig.keyGen();
        final message = Uint8List.fromList('empty'.codeUnits);
        expect(
          () => ringSig.ringSign(kp.signingKey, message, <Uint8List>[]),
          throwsArgumentError,
        );
      });
    });
  }

  group('Prf', () {
    final prf = const Prf();

    test('determinism: same inputs produce same output', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0x42));
      final sid = Uint8List.fromList('session-id'.codeUnits);
      final out1 = prf.evaluate(key, sid, 64);
      final out2 = prf.evaluate(key, sid, 64);
      expect(out1, equals(out2));
    });

    test('produces correct number of bytes for various lengths', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0xAA));
      final sid = Uint8List.fromList('test-sid'.codeUnits);

      for (final length in [1, 16, 32, 33, 64, 100, 256]) {
        final output = prf.evaluate(key, sid, length);
        expect(output.length, length, reason: 'length=$length');
      }
    });

    test('different keys produce different outputs', () {
      final key1 = Uint8List.fromList(List<int>.filled(32, 0x01));
      final key2 = Uint8List.fromList(List<int>.filled(32, 0x02));
      final sid = Uint8List.fromList('same-sid'.codeUnits);
      final out1 = prf.evaluate(key1, sid, 32);
      final out2 = prf.evaluate(key2, sid, 32);
      expect(out1, isNot(equals(out2)));
    });

    test('different session IDs produce different outputs', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0x01));
      final sid1 = Uint8List.fromList('sid-one'.codeUnits);
      final sid2 = Uint8List.fromList('sid-two'.codeUnits);
      final out1 = prf.evaluate(key, sid1, 32);
      final out2 = prf.evaluate(key, sid2, 32);
      expect(out1, isNot(equals(out2)));
    });

    test('throws on non-positive output length', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0x01));
      final sid = Uint8List.fromList('test'.codeUnits);
      expect(() => prf.evaluate(key, sid, 0), throwsA(isA<ArgumentError>()));
      expect(() => prf.evaluate(key, sid, -1), throwsA(isA<ArgumentError>()));
    });

    test('throws on excessive output length', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0x01));
      final sid = Uint8List.fromList('test'.codeUnits);
      expect(
        () => prf.evaluate(key, sid, 255 * 32 + 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('shorter output is prefix of longer output', () {
      final key = Uint8List.fromList(List<int>.filled(32, 0xBB));
      final sid = Uint8List.fromList('prefix-test'.codeUnits);
      final short = prf.evaluate(key, sid, 32);
      final long = prf.evaluate(key, sid, 64);
      expect(long.sublist(0, 32), equals(short));
    });
  });

  group('Ext', () {
    final ext = const Ext();

    test('produces 32 bytes', () {
      final seed = Uint8List.fromList(List<int>.filled(32, 0x01));
      final input = Uint8List.fromList('test input'.codeUnits);
      final output = ext.extract(seed, input);
      expect(output.length, 32);
    });

    test('deterministic: same inputs produce same output', () {
      final seed = Uint8List.fromList(List<int>.filled(32, 0x42));
      final input = Uint8List.fromList('deterministic'.codeUnits);
      final out1 = ext.extract(seed, input);
      final out2 = ext.extract(seed, input);
      expect(out1, equals(out2));
    });

    test('different seeds produce different outputs', () {
      final seed1 = Uint8List.fromList(List<int>.filled(32, 0x01));
      final seed2 = Uint8List.fromList(List<int>.filled(32, 0x02));
      final input = Uint8List.fromList('same input'.codeUnits);
      final out1 = ext.extract(seed1, input);
      final out2 = ext.extract(seed2, input);
      expect(out1, isNot(equals(out2)));
    });

    test('different inputs produce different outputs', () {
      final seed = Uint8List.fromList(List<int>.filled(32, 0x01));
      final input1 = Uint8List.fromList('input one'.codeUnits);
      final input2 = Uint8List.fromList('input two'.codeUnits);
      final out1 = ext.extract(seed, input1);
      final out2 = ext.extract(seed, input2);
      expect(out1, isNot(equals(out2)));
    });

    test('throws on wrong seed length', () {
      final shortSeed = Uint8List(16);
      final longSeed = Uint8List(64);
      final input = Uint8List.fromList('test'.codeUnits);
      expect(
        () => ext.extract(shortSeed, input),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => ext.extract(longSeed, input), throwsA(isA<ArgumentError>()));
    });

    test('works with empty input', () {
      final seed = Uint8List.fromList(List<int>.filled(32, 0x01));
      final input = Uint8List(0);
      final output = ext.extract(seed, input);
      expect(output.length, 32);
    });
  });

  group('CryptoProvider', () {
    test('default level is l192', () {
      const provider = CryptoProvider();
      expect(provider.level, SecurityLevel.l192);
    });

    for (final level in SecurityLevel.values) {
      test('creates instances for ${level.name}', () {
        final provider = CryptoProvider(level: level);
        expect(provider.kem, isA<Kem>());
        expect(provider.sig, isA<Sig>());
        expect(provider.ringSig, isA<RingSig>());
        expect(provider.prf, isA<Prf>());
        expect(provider.ext, isA<Ext>());
      });

      test('KEM from provider works for ${level.name}', () {
        final provider = CryptoProvider(level: level);
        final kem = provider.kem;
        final kp = kem.keyGen();
        final enc = kem.encap(kp.publicKey);
        final ss = kem.decap(kp.secretKey, enc.ciphertext);
        expect(ss, equals(enc.sharedSecret));
      });

      test('SIG from provider works for ${level.name}', () {
        final provider = CryptoProvider(level: level);
        final sig = provider.sig;
        final kp = sig.keyGen();
        final message = Uint8List.fromList('provider test'.codeUnits);
        final signature = sig.sign(kp.signingKey, message);
        expect(sig.verify(kp.verificationKey, message, signature), isTrue);
      });

      test('RingSig from provider works for ${level.name}', () {
        final provider = CryptoProvider(level: level);
        final rs = provider.ringSig;
        final kp1 = rs.keyGen();
        final kp2 = rs.keyGen();
        final ring = <Uint8List>[kp1.verificationKey, kp2.verificationKey];
        final message = Uint8List.fromList('provider ring'.codeUnits);
        final signature = rs.ringSign(kp1.signingKey, message, ring);
        expect(rs.ringVerify(message, signature, ring), isTrue);
      });
    }
  });

  group('Integration', () {
    test('PRF produces enough bytes for prfOutputSize at all levels', () {
      const prf = Prf();
      final key = Uint8List.fromList(List<int>.filled(32, 0xCC));
      final sid = Uint8List.fromList('integration-sid'.codeUnits);

      for (final level in SecurityLevel.values) {
        final output = prf.evaluate(key, sid, level.prfOutputSize);
        expect(
          output.length,
          level.prfOutputSize,
          reason: '${level.name} prfOutputSize',
        );

        // Split into session key and OTP portions
        final sessionKey = output.sublist(0, level.sessionKeySize);
        final otp = output.sublist(level.sessionKeySize);
        expect(sessionKey.length, level.sessionKeySize);
        expect(otp.length, level.sigSignatureSize);
      }
    });

    test('Ext output can be used as PRF key', () {
      const ext = Ext();
      const prf = Prf();
      final seed = Uint8List.fromList(List<int>.filled(32, 0xDD));
      final kemSs = Uint8List.fromList(List<int>.filled(32, 0xEE));
      final sid = Uint8List.fromList('chain-test'.codeUnits);

      final extractedKey = ext.extract(seed, kemSs);
      expect(extractedKey.length, 32);

      final prfOutput = prf.evaluate(extractedKey, sid, 64);
      expect(prfOutput.length, 64);
    });
  });
}
