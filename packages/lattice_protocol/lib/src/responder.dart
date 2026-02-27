import 'dart:typed_data';

import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/src/key_types.dart';
import 'package:lattice_protocol/src/message_types.dart';

/// The result of session creation on the responder (Bob) side.
class ResponderSessionResult {
  /// Creates a [ResponderSessionResult].
  const ResponderSessionResult({
    required this.sessionKey,
    required this.sessionId,
    required this.message,
  });

  /// The derived session key `kB`.
  final Uint8List sessionKey;

  /// The session identifier `sid`.
  final SessionId sessionId;

  /// The key-exchange message `(C, CT, c)` to send to Alice.
  final KeyExchangeMessage message;
}

/// The responder (Bob) side of the SC-AKE protocol.
///
/// Bob performs the full key-exchange in a single step: verify Alice's
/// pre-key bundle, encapsulate shared secrets, derive keys, sign the session
/// ID, and produce the key-exchange message.
class Responder {
  /// Creates a [Responder] using the given [crypto] provider.
  const Responder(this.crypto);

  /// The cryptographic provider supplying KEM, SIG, Ext, and PRF primitives.
  final CryptoProvider crypto;

  /// Creates a session from Alice's pre-key bundle.
  ///
  /// Protocol steps (Figure 4, Bob's flow):
  /// 1. Verify `SIG.Verify(vkA, ekT, sigmaA)`
  /// 2. `(K, C) <- KEM.Encap(ekA); (KT, CT) <- wKEM.Encap(ekT)`
  /// 3. `K1 <- Ext_s(K); K2 <- Ext_s(KT)`
  /// 4. `sid := A || B || lpkA || lpkB || ekT || C || CT`
  /// 5. `kB || k_tilde <- F_K1(sid) XOR F_K2(sid)`
  /// 6. `sigma <- SIG.Sign(skB, sid); c <- sigma XOR k_tilde`
  /// 7. Output `(C, CT, c)` and session key `kB`
  ///
  /// Throws [StateError] if Alice's pre-key signature is invalid.
  ResponderSessionResult createSession({
    required String identityA,
    required String identityB,
    required PreKeyBundle bundleA,
    required LongTermPublicKey lpkB,
    required LongTermSecretKey lskB,
    required Uint8List seed,
  }) {
    // 1. Verify Alice's signature on her ephemeral key
    if (!crypto.sig.verify(
      bundleA.longTermPublicKey.verificationKey,
      bundleA.ephemeralPublicKey,
      bundleA.signature,
    )) {
      throw StateError('Session creation failed: invalid pre-key signature');
    }

    // 2. Encapsulate shared secrets under both keys
    final kemResult = crypto.kem.encap(
      bundleA.longTermPublicKey.encapsulationKey,
    );
    final wKemResult = crypto.kem.encap(bundleA.ephemeralPublicKey);

    // 3. Extract uniform keys
    final k1 = crypto.ext.extract(seed, kemResult.sharedSecret);
    final k2 = crypto.ext.extract(seed, wKemResult.sharedSecret);

    // 4. Build session ID
    final sid = SessionId.build(
      identityA: identityA,
      identityB: identityB,
      lpkA: bundleA.longTermPublicKey,
      lpkB: lpkB,
      ephemeralPublicKey: bundleA.ephemeralPublicKey,
      ciphertext: kemResult.ciphertext,
      ephemeralCiphertext: wKemResult.ciphertext,
    );

    // 5. PRF output: kB || k_tilde = F_K1(sid) XOR F_K2(sid)
    final outputLen = crypto.kem.level.prfOutputSize;
    final prfOut1 = crypto.prf.evaluate(k1, sid.data, outputLen);
    final prfOut2 = crypto.prf.evaluate(k2, sid.data, outputLen);

    final combined = Uint8List(outputLen);
    for (var i = 0; i < outputLen; i++) {
      combined[i] = prfOut1[i] ^ prfOut2[i];
    }

    final sessionKeySize = crypto.kem.level.sessionKeySize;
    final kB = Uint8List.fromList(
      Uint8List.sublistView(combined, 0, sessionKeySize),
    );
    final kTilde = Uint8List.sublistView(combined, sessionKeySize);

    // 6. Sign the session ID, then encrypt the signature
    final sigma = crypto.sig.sign(lskB.signingKey, sid.data);
    final c = Uint8List(sigma.length);
    for (var i = 0; i < sigma.length; i++) {
      c[i] = sigma[i] ^ kTilde[i];
    }

    // 7. Build message and return
    final msg = KeyExchangeMessage(
      ciphertext: kemResult.ciphertext,
      ephemeralCiphertext: wKemResult.ciphertext,
      encryptedSignature: c,
    );

    return ResponderSessionResult(sessionKey: kB, sessionId: sid, message: msg);
  }
}
