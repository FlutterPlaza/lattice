import 'dart:math';
import 'dart:typed_data';

import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/lattice_protocol.dart';
import 'package:test/test.dart';

/// Generates a deterministic 32-byte seed for testing.
Uint8List _testSeed() {
  final rng = Random.secure();
  final seed = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    seed[i] = rng.nextInt(256);
  }
  return seed;
}

/// Runs a full SC-AKE handshake and returns both session results.
({
  InitiatorSessionResult alice,
  ResponderSessionResult bob,
  RegistrationResult regA,
  RegistrationResult regB,
  EphemeralPreKey preKey,
})
_runHandshake(CryptoProvider crypto) {
  final reg = Registration(crypto);
  final initiator = Initiator(crypto);
  final responder = Responder(crypto);

  // 1. Alice: Registration
  final regA = reg.generate();
  // 2. Bob: Registration
  final regB = reg.generate();

  // 3. Alice: Upload pre-key
  final uploadResult = initiator.uploadPreKey(
    lpkA: regA.publicKey,
    lskA: regA.secretKey,
  );

  // Shared seed (public parameter in deployment)
  final seed = _testSeed();

  // 4. Bob: Create session from Alice's bundle
  final bobResult = responder.createSession(
    identityA: 'alice',
    identityB: 'bob',
    bundleA: uploadResult.bundle,
    lpkB: regB.publicKey,
    lskB: regB.secretKey,
    seed: seed,
  );

  // 5. Alice: Finalize session with Bob's message
  final aliceResult = initiator.finalizeSession(
    identityA: 'alice',
    identityB: 'bob',
    lpkA: regA.publicKey,
    lpkB: regB.publicKey,
    lskA: regA.secretKey,
    preKey: uploadResult.preKey,
    message: bobResult.message,
    seed: seed,
  );

  return (
    alice: aliceResult,
    bob: bobResult,
    regA: regA,
    regB: regB,
    preKey: uploadResult.preKey,
  );
}

void main() {
  group('Registration', () {
    test('generates valid key pairs at default level', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final result = reg.generate();

      expect(
        result.publicKey.encapsulationKey.length,
        equals(crypto.kem.level.kemPublicKeySize),
      );
      expect(
        result.publicKey.verificationKey.length,
        equals(crypto.sig.level.sigPublicKeySize),
      );
      expect(
        result.secretKey.decapsulationKey.length,
        equals(crypto.kem.level.kemSecretKeySize),
      );
    });

    test('generates different keys each time', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final r1 = reg.generate();
      final r2 = reg.generate();

      expect(
        r1.publicKey.encapsulationKey,
        isNot(equals(r2.publicKey.encapsulationKey)),
      );
      expect(
        r1.publicKey.verificationKey,
        isNot(equals(r2.publicKey.verificationKey)),
      );
    });

    for (final level in SecurityLevel.values) {
      test('generates valid key pairs at ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final reg = Registration(crypto);
        final result = reg.generate();

        expect(
          result.publicKey.encapsulationKey.length,
          equals(level.kemPublicKeySize),
        );
        expect(
          result.publicKey.verificationKey.length,
          equals(level.sigPublicKeySize),
        );
      });
    }
  });

  group('Initiator.uploadPreKey', () {
    test('produces valid pre-key bundle', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final initiator = Initiator(crypto);

      final regResult = reg.generate();
      final uploadResult = initiator.uploadPreKey(
        lpkA: regResult.publicKey,
        lskA: regResult.secretKey,
      );

      // The bundle should contain Alice's long-term public key
      expect(
        uploadResult.bundle.longTermPublicKey.encapsulationKey,
        equals(regResult.publicKey.encapsulationKey),
      );
      expect(
        uploadResult.bundle.longTermPublicKey.verificationKey,
        equals(regResult.publicKey.verificationKey),
      );

      // The ephemeral public key in bundle and preKey should match
      expect(
        uploadResult.bundle.ephemeralPublicKey,
        equals(uploadResult.preKey.ephemeralPublicKey),
      );

      // The signature should match
      expect(
        uploadResult.bundle.signature,
        equals(uploadResult.preKey.signature),
      );

      // The signature should verify
      expect(
        crypto.sig.verify(
          regResult.publicKey.verificationKey,
          uploadResult.preKey.ephemeralPublicKey,
          uploadResult.preKey.signature,
        ),
        isTrue,
      );
    });
  });

  group('SC-AKE Handshake', () {
    test('Alice and Bob derive the same session key (kA == kB)', () {
      final crypto = const CryptoProvider();
      final result = _runHandshake(crypto);

      // The key assertion: both parties derive the same session key
      expect(result.alice.sessionKey, equals(result.bob.sessionKey));
    });

    test('session IDs match between Alice and Bob', () {
      final crypto = const CryptoProvider();
      final result = _runHandshake(crypto);

      expect(result.alice.sessionId.data, equals(result.bob.sessionId.data));
    });

    test('session key has correct size', () {
      final crypto = const CryptoProvider();
      final result = _runHandshake(crypto);

      expect(
        result.alice.sessionKey.length,
        equals(crypto.kem.level.sessionKeySize),
      );
    });

    test('different sessions produce different keys', () {
      final crypto = const CryptoProvider();
      final r1 = _runHandshake(crypto);
      final r2 = _runHandshake(crypto);

      expect(r1.alice.sessionKey, isNot(equals(r2.alice.sessionKey)));
    });

    for (final level in SecurityLevel.values) {
      test('works at security level ${level.name}', () {
        final crypto = CryptoProvider(level: level);
        final result = _runHandshake(crypto);

        expect(result.alice.sessionKey, equals(result.bob.sessionKey));
        expect(result.alice.sessionKey.length, equals(level.sessionKeySize));
      });
    }
  });

  group('Tampered ciphertext', () {
    test('tampered KEM ciphertext causes session finalization to fail', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final initiator = Initiator(crypto);
      final responder = Responder(crypto);

      final regA = reg.generate();
      final regB = reg.generate();

      final uploadResult = initiator.uploadPreKey(
        lpkA: regA.publicKey,
        lskA: regA.secretKey,
      );

      final seed = _testSeed();

      final bobResult = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: uploadResult.bundle,
        lpkB: regB.publicKey,
        lskB: regB.secretKey,
        seed: seed,
      );

      // Tamper with the KEM ciphertext
      final tamperedCiphertext = Uint8List.fromList(
        bobResult.message.ciphertext,
      );
      tamperedCiphertext[0] ^= 0xFF;

      final tamperedMsg = KeyExchangeMessage(
        ciphertext: tamperedCiphertext,
        ephemeralCiphertext: bobResult.message.ephemeralCiphertext,
        encryptedSignature: bobResult.message.encryptedSignature,
      );

      expect(
        () => initiator.finalizeSession(
          identityA: 'alice',
          identityB: 'bob',
          lpkA: regA.publicKey,
          lpkB: regB.publicKey,
          lskA: regA.secretKey,
          preKey: uploadResult.preKey,
          message: tamperedMsg,
          seed: seed,
        ),
        throwsStateError,
      );
    });

    test(
      'tampered ephemeral ciphertext causes session finalization to fail',
      () {
        final crypto = const CryptoProvider();
        final reg = Registration(crypto);
        final initiator = Initiator(crypto);
        final responder = Responder(crypto);

        final regA = reg.generate();
        final regB = reg.generate();

        final uploadResult = initiator.uploadPreKey(
          lpkA: regA.publicKey,
          lskA: regA.secretKey,
        );

        final seed = _testSeed();

        final bobResult = responder.createSession(
          identityA: 'alice',
          identityB: 'bob',
          bundleA: uploadResult.bundle,
          lpkB: regB.publicKey,
          lskB: regB.secretKey,
          seed: seed,
        );

        // Tamper with the ephemeral ciphertext
        final tamperedEphCiphertext = Uint8List.fromList(
          bobResult.message.ephemeralCiphertext,
        );
        tamperedEphCiphertext[0] ^= 0xFF;

        final tamperedMsg = KeyExchangeMessage(
          ciphertext: bobResult.message.ciphertext,
          ephemeralCiphertext: tamperedEphCiphertext,
          encryptedSignature: bobResult.message.encryptedSignature,
        );

        expect(
          () => initiator.finalizeSession(
            identityA: 'alice',
            identityB: 'bob',
            lpkA: regA.publicKey,
            lpkB: regB.publicKey,
            lskA: regA.secretKey,
            preKey: uploadResult.preKey,
            message: tamperedMsg,
            seed: seed,
          ),
          throwsStateError,
        );
      },
    );
  });

  group('Tampered signature in bundle', () {
    test('tampered pre-key signature causes session creation to fail', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final initiator = Initiator(crypto);
      final responder = Responder(crypto);

      final regA = reg.generate();
      final regB = reg.generate();

      final uploadResult = initiator.uploadPreKey(
        lpkA: regA.publicKey,
        lskA: regA.secretKey,
      );

      // Tamper with the signature in the bundle
      final tamperedSig = Uint8List.fromList(uploadResult.bundle.signature);
      tamperedSig[0] ^= 0xFF;

      final tamperedBundle = PreKeyBundle(
        longTermPublicKey: uploadResult.bundle.longTermPublicKey,
        ephemeralPublicKey: uploadResult.bundle.ephemeralPublicKey,
        signature: tamperedSig,
      );

      final seed = _testSeed();

      expect(
        () => responder.createSession(
          identityA: 'alice',
          identityB: 'bob',
          bundleA: tamperedBundle,
          lpkB: regB.publicKey,
          lskB: regB.secretKey,
          seed: seed,
        ),
        throwsStateError,
      );
    });
  });

  group('Tampered encrypted signature', () {
    test(
      'tampered encrypted signature causes session finalization to fail',
      () {
        final crypto = const CryptoProvider();
        final reg = Registration(crypto);
        final initiator = Initiator(crypto);
        final responder = Responder(crypto);

        final regA = reg.generate();
        final regB = reg.generate();

        final uploadResult = initiator.uploadPreKey(
          lpkA: regA.publicKey,
          lskA: regA.secretKey,
        );

        final seed = _testSeed();

        final bobResult = responder.createSession(
          identityA: 'alice',
          identityB: 'bob',
          bundleA: uploadResult.bundle,
          lpkB: regB.publicKey,
          lskB: regB.secretKey,
          seed: seed,
        );

        // Tamper with the encrypted signature
        final tamperedEncSig = Uint8List.fromList(
          bobResult.message.encryptedSignature,
        );
        tamperedEncSig[0] ^= 0xFF;

        final tamperedMsg = KeyExchangeMessage(
          ciphertext: bobResult.message.ciphertext,
          ephemeralCiphertext: bobResult.message.ephemeralCiphertext,
          encryptedSignature: tamperedEncSig,
        );

        expect(
          () => initiator.finalizeSession(
            identityA: 'alice',
            identityB: 'bob',
            lpkA: regA.publicKey,
            lpkB: regB.publicKey,
            lskA: regA.secretKey,
            preKey: uploadResult.preKey,
            message: tamperedMsg,
            seed: seed,
          ),
          throwsStateError,
        );
      },
    );
  });

  group('Multiple concurrent sessions', () {
    test('different user pairs derive independent session keys', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final initiator = Initiator(crypto);
      final responder = Responder(crypto);

      // Pair 1: Alice <-> Bob
      final regAlice = reg.generate();
      final regBob = reg.generate();

      // Pair 2: Charlie <-> Dave
      final regCharlie = reg.generate();
      final regDave = reg.generate();

      final seed = _testSeed();

      // Session 1: Alice <-> Bob
      final uploadAB = initiator.uploadPreKey(
        lpkA: regAlice.publicKey,
        lskA: regAlice.secretKey,
      );
      final bobSession = responder.createSession(
        identityA: 'alice',
        identityB: 'bob',
        bundleA: uploadAB.bundle,
        lpkB: regBob.publicKey,
        lskB: regBob.secretKey,
        seed: seed,
      );
      final aliceSession = initiator.finalizeSession(
        identityA: 'alice',
        identityB: 'bob',
        lpkA: regAlice.publicKey,
        lpkB: regBob.publicKey,
        lskA: regAlice.secretKey,
        preKey: uploadAB.preKey,
        message: bobSession.message,
        seed: seed,
      );

      // Session 2: Charlie <-> Dave
      final uploadCD = initiator.uploadPreKey(
        lpkA: regCharlie.publicKey,
        lskA: regCharlie.secretKey,
      );
      final daveSession = responder.createSession(
        identityA: 'charlie',
        identityB: 'dave',
        bundleA: uploadCD.bundle,
        lpkB: regDave.publicKey,
        lskB: regDave.secretKey,
        seed: seed,
      );
      final charlieSession = initiator.finalizeSession(
        identityA: 'charlie',
        identityB: 'dave',
        lpkA: regCharlie.publicKey,
        lpkB: regDave.publicKey,
        lskA: regCharlie.secretKey,
        preKey: uploadCD.preKey,
        message: daveSession.message,
        seed: seed,
      );

      // Each pair agrees on their own key
      expect(aliceSession.sessionKey, equals(bobSession.sessionKey));
      expect(charlieSession.sessionKey, equals(daveSession.sessionKey));

      // Different pairs have different keys
      expect(aliceSession.sessionKey, isNot(equals(charlieSession.sessionKey)));
    });
  });

  group('Serialization round-trips', () {
    test('LongTermPublicKey serialize/deserialize', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final result = reg.generate();

      final serialized = result.publicKey.serialize();
      final deserialized = LongTermPublicKey.deserialize(serialized);

      expect(
        deserialized.encapsulationKey,
        equals(result.publicKey.encapsulationKey),
      );
      expect(
        deserialized.verificationKey,
        equals(result.publicKey.verificationKey),
      );
    });

    test('PreKeyBundle serialize/deserialize', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);
      final initiator = Initiator(crypto);

      final regResult = reg.generate();
      final uploadResult = initiator.uploadPreKey(
        lpkA: regResult.publicKey,
        lskA: regResult.secretKey,
      );

      final serialized = uploadResult.bundle.serialize();
      final deserialized = PreKeyBundle.deserialize(serialized);

      expect(
        deserialized.longTermPublicKey.encapsulationKey,
        equals(uploadResult.bundle.longTermPublicKey.encapsulationKey),
      );
      expect(
        deserialized.longTermPublicKey.verificationKey,
        equals(uploadResult.bundle.longTermPublicKey.verificationKey),
      );
      expect(
        deserialized.ephemeralPublicKey,
        equals(uploadResult.bundle.ephemeralPublicKey),
      );
      expect(deserialized.signature, equals(uploadResult.bundle.signature));
    });

    test('KeyExchangeMessage serialize/deserialize', () {
      final crypto = const CryptoProvider();
      final result = _runHandshake(crypto);

      final serialized = result.bob.message.serialize();
      final deserialized = KeyExchangeMessage.deserialize(serialized);

      expect(deserialized.ciphertext, equals(result.bob.message.ciphertext));
      expect(
        deserialized.ephemeralCiphertext,
        equals(result.bob.message.ephemeralCiphertext),
      );
      expect(
        deserialized.encryptedSignature,
        equals(result.bob.message.encryptedSignature),
      );
    });

    test('SessionId round-trip through build', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);

      final regA = reg.generate();
      final regB = reg.generate();

      final ciphertext = Uint8List(64);
      final ephCiphertext = Uint8List(64);
      final ephPk = Uint8List(32);

      final sid1 = SessionId.build(
        identityA: 'alice',
        identityB: 'bob',
        lpkA: regA.publicKey,
        lpkB: regB.publicKey,
        ephemeralPublicKey: ephPk,
        ciphertext: ciphertext,
        ephemeralCiphertext: ephCiphertext,
      );

      final sid2 = SessionId.build(
        identityA: 'alice',
        identityB: 'bob',
        lpkA: regA.publicKey,
        lpkB: regB.publicKey,
        ephemeralPublicKey: ephPk,
        ciphertext: ciphertext,
        ephemeralCiphertext: ephCiphertext,
      );

      // Same inputs produce same session ID
      expect(sid1.data, equals(sid2.data));
    });

    test('SessionId differs with different identities', () {
      final crypto = const CryptoProvider();
      final reg = Registration(crypto);

      final regA = reg.generate();
      final regB = reg.generate();

      final ciphertext = Uint8List(64);
      final ephCiphertext = Uint8List(64);
      final ephPk = Uint8List(32);

      final sid1 = SessionId.build(
        identityA: 'alice',
        identityB: 'bob',
        lpkA: regA.publicKey,
        lpkB: regB.publicKey,
        ephemeralPublicKey: ephPk,
        ciphertext: ciphertext,
        ephemeralCiphertext: ephCiphertext,
      );

      final sid2 = SessionId.build(
        identityA: 'alice',
        identityB: 'charlie',
        lpkA: regA.publicKey,
        lpkB: regB.publicKey,
        ephemeralPublicKey: ephPk,
        ciphertext: ciphertext,
        ephemeralCiphertext: ephCiphertext,
      );

      expect(sid1.data, isNot(equals(sid2.data)));
    });
  });

  group('Serialization helpers', () {
    test('writeLengthPrefixed / readLengthPrefixed round-trip', () {
      final builder = BytesBuilder(copy: false);
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      Serialization.writeLengthPrefixed(builder, data);

      final encoded = builder.takeBytes();
      final (decoded, consumed) = Serialization.readLengthPrefixed(encoded, 0);

      expect(decoded, equals(data));
      expect(consumed, equals(4 + data.length));
    });

    test('writeLengthPrefixedString / readLengthPrefixedString round-trip', () {
      final builder = BytesBuilder(copy: false);
      const testStr = 'Hello, World!';
      Serialization.writeLengthPrefixedString(builder, testStr);

      final encoded = builder.takeBytes();
      final (decoded, consumed) = Serialization.readLengthPrefixedString(
        encoded,
        0,
      );

      expect(decoded, equals(testStr));
      expect(consumed, equals(4 + testStr.length));
    });

    test('multiple fields can be read sequentially', () {
      final builder = BytesBuilder(copy: false);
      final d1 = Uint8List.fromList([10, 20, 30]);
      final d2 = Uint8List.fromList([40, 50]);
      Serialization.writeLengthPrefixed(builder, d1);
      Serialization.writeLengthPrefixed(builder, d2);

      final encoded = builder.takeBytes();
      var offset = 0;
      final (r1, c1) = Serialization.readLengthPrefixed(encoded, offset);
      offset += c1;
      final (r2, _) = Serialization.readLengthPrefixed(encoded, offset);

      expect(r1, equals(d1));
      expect(r2, equals(d2));
    });

    test('readLengthPrefixed throws on insufficient data', () {
      final shortData = Uint8List.fromList([0, 0]);
      expect(
        () => Serialization.readLengthPrefixed(shortData, 0),
        throwsRangeError,
      );
    });

    test('readLengthPrefixed throws on insufficient payload', () {
      // Length prefix says 100 bytes, but only 2 bytes of payload
      final badData = Uint8List.fromList([0, 0, 0, 100, 1, 2]);
      expect(
        () => Serialization.readLengthPrefixed(badData, 0),
        throwsRangeError,
      );
    });

    test('empty data round-trips correctly', () {
      final builder = BytesBuilder(copy: false);
      final empty = Uint8List(0);
      Serialization.writeLengthPrefixed(builder, empty);

      final encoded = builder.takeBytes();
      final (decoded, consumed) = Serialization.readLengthPrefixed(encoded, 0);

      expect(decoded, equals(empty));
      expect(consumed, equals(4));
    });
  });

  group('Store tests', () {
    group('InMemoryIdentityStore', () {
      test('save and retrieve identity', () async {
        final store = InMemoryIdentityStore();
        final crypto = const CryptoProvider();
        final reg = Registration(crypto);
        final result = reg.generate();

        await store.saveIdentity('user1', result.publicKey, result.secretKey);

        final pk = await store.getPublicKey('user1');
        final sk = await store.getSecretKey('user1');

        expect(pk, isNotNull);
        expect(pk!.encapsulationKey, equals(result.publicKey.encapsulationKey));
        expect(pk.verificationKey, equals(result.publicKey.verificationKey));
        expect(sk, isNotNull);
        expect(sk!.decapsulationKey, equals(result.secretKey.decapsulationKey));
      });

      test('returns null for unknown user', () async {
        final store = InMemoryIdentityStore();

        expect(await store.getPublicKey('unknown'), isNull);
        expect(await store.getSecretKey('unknown'), isNull);
      });
    });

    group('InMemoryPreKeyStore', () {
      test('save, get, and remove pre-key', () async {
        final store = InMemoryPreKeyStore();
        final crypto = const CryptoProvider();
        final reg = Registration(crypto);
        final initiator = Initiator(crypto);

        final regResult = reg.generate();
        final uploadResult = initiator.uploadPreKey(
          lpkA: regResult.publicKey,
          lskA: regResult.secretKey,
        );

        await store.savePreKey('user1', uploadResult.preKey);

        final retrieved = await store.getPreKey('user1');
        expect(retrieved, isNotNull);
        expect(
          retrieved!.ephemeralPublicKey,
          equals(uploadResult.preKey.ephemeralPublicKey),
        );

        await store.removePreKey('user1');
        expect(await store.getPreKey('user1'), isNull);
      });

      test('returns null for unknown user', () async {
        final store = InMemoryPreKeyStore();
        expect(await store.getPreKey('unknown'), isNull);
      });
    });

    group('InMemorySessionStore', () {
      test('save, get, and remove session', () async {
        final store = InMemorySessionStore();
        final crypto = const CryptoProvider();
        final result = _runHandshake(crypto);

        final session = Session(
          sessionId: result.alice.sessionId,
          sessionKey: result.alice.sessionKey,
          localIdentity: 'alice',
          remoteIdentity: 'bob',
        );

        await store.saveSession('bob', session);

        final retrieved = await store.getSession('bob');
        expect(retrieved, isNotNull);
        expect(retrieved!.localIdentity, equals('alice'));
        expect(retrieved.remoteIdentity, equals('bob'));
        expect(retrieved.sessionKey, equals(result.alice.sessionKey));

        await store.removeSession('bob');
        expect(await store.getSession('bob'), isNull);
      });

      test('getAllSessions returns all saved sessions', () async {
        final store = InMemorySessionStore();
        final crypto = const CryptoProvider();
        final result = _runHandshake(crypto);

        final session1 = Session(
          sessionId: result.alice.sessionId,
          sessionKey: result.alice.sessionKey,
          localIdentity: 'alice',
          remoteIdentity: 'bob',
        );
        final session2 = Session(
          sessionId: result.alice.sessionId,
          sessionKey: result.alice.sessionKey,
          localIdentity: 'alice',
          remoteIdentity: 'charlie',
        );

        await store.saveSession('bob', session1);
        await store.saveSession('charlie', session2);

        final all = await store.getAllSessions();
        expect(all.length, equals(2));
      });

      test('returns null for unknown peer', () async {
        final store = InMemorySessionStore();
        expect(await store.getSession('unknown'), isNull);
      });

      test('getAllSessions returns empty list when no sessions', () async {
        final store = InMemorySessionStore();
        final all = await store.getAllSessions();
        expect(all, isEmpty);
      });
    });
  });

  group('Session', () {
    test('creation and field access', () {
      final sid = SessionId(Uint8List.fromList([1, 2, 3]));
      final key = Uint8List.fromList([4, 5, 6]);
      final now = DateTime.now();

      final session = Session(
        sessionId: sid,
        sessionKey: key,
        localIdentity: 'alice',
        remoteIdentity: 'bob',
        createdAt: now,
      );

      expect(session.sessionId.data, equals(sid.data));
      expect(session.sessionKey, equals(key));
      expect(session.localIdentity, equals('alice'));
      expect(session.remoteIdentity, equals('bob'));
      expect(session.createdAt, equals(now));
    });

    test('defaults createdAt to now when not provided', () {
      final before = DateTime.now();
      final session = Session(
        sessionId: SessionId(Uint8List(0)),
        sessionKey: Uint8List(0),
        localIdentity: 'alice',
        remoteIdentity: 'bob',
      );
      final after = DateTime.now();

      expect(
        session.createdAt.isAfter(before) ||
            session.createdAt.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        session.createdAt.isBefore(after) ||
            session.createdAt.isAtSameMomentAs(after),
        isTrue,
      );
    });
  });
}
