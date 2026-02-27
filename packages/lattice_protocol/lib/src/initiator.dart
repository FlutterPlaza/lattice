import 'dart:typed_data';

import 'package:lattice_crypto/lattice_crypto.dart';
import 'package:lattice_protocol/src/key_types.dart';
import 'package:lattice_protocol/src/message_types.dart';

/// The result of uploading a pre-key: the [preKey] (containing the secret
/// ephemeral key) and the [bundle] to publish to the server.
class PreKeyUploadResult {
  /// Creates a [PreKeyUploadResult].
  const PreKeyUploadResult({required this.preKey, required this.bundle});

  /// The full ephemeral pre-key (including the secret decapsulation key).
  final EphemeralPreKey preKey;

  /// The pre-key bundle to publish to the server (public components only).
  final PreKeyBundle bundle;
}

/// The result of session finalization on the initiator (Alice) side.
class InitiatorSessionResult {
  /// Creates an [InitiatorSessionResult].
  const InitiatorSessionResult({
    required this.sessionKey,
    required this.sessionId,
  });

  /// The derived session key `kA`.
  final Uint8List sessionKey;

  /// The session identifier `sid`.
  final SessionId sessionId;
}

/// The initiator (Alice) side of the SC-AKE protocol.
///
/// Alice performs two operations:
/// 1. [uploadPreKey]: Generate an ephemeral pre-key and sign it.
/// 2. [finalizeSession]: After receiving Bob's key-exchange message,
///    decapsulate, derive keys, and verify Bob's signature.
class Initiator {
  /// Creates an [Initiator] using the given [crypto] provider.
  const Initiator(this.crypto);

  /// The cryptographic provider supplying KEM, SIG, Ext, and PRF primitives.
  final CryptoProvider crypto;

  /// Generates an ephemeral pre-key and signs it with Alice's long-term
  /// signing key.
  ///
  /// Returns a [PreKeyUploadResult] containing:
  /// - `preKey`: the full ephemeral pre-key (keep `dkT` secret)
  /// - `bundle`: the pre-key bundle to publish to the server
  ///
  /// Protocol step: `wKEM.KeyGen -> (ekT, dkT); SIG.Sign(skA, ekT) -> sigmaA`
  PreKeyUploadResult uploadPreKey({
    required LongTermPublicKey lpkA,
    required LongTermSecretKey lskA,
  }) {
    // wKEM.KeyGen (use same KEM for simplicity)
    final ephKp = crypto.kem.keyGen();

    // Sign the ephemeral public key
    final sigma = crypto.sig.sign(lskA.signingKey, ephKp.publicKey);

    final preKey = EphemeralPreKey(
      ephemeralPublicKey: ephKp.publicKey,
      ephemeralSecretKey: ephKp.secretKey,
      signature: sigma,
    );

    final bundle = PreKeyBundle(
      longTermPublicKey: lpkA,
      ephemeralPublicKey: ephKp.publicKey,
      signature: sigma,
    );

    return PreKeyUploadResult(preKey: preKey, bundle: bundle);
  }

  /// Finalizes the session on Alice's side after receiving Bob's
  /// [KeyExchangeMessage].
  ///
  /// Protocol steps (Figure 4, Alice's flow):
  /// 1. `K <- KEM.Decap(dkA, C); KT <- wKEM.Decap(dkT, CT)`
  /// 2. `K1 <- Ext_s(K); K2 <- Ext_s(KT)`
  /// 3. `sid := A || B || lpkA || lpkB || ekT || C || CT`
  /// 4. `kA || k_tilde <- F_K1(sid) XOR F_K2(sid)`
  /// 5. `sigma <- c XOR k_tilde; verify SIG.Verify(vkB, sid, sigma)`
  /// 6. Output session key `kA`
  ///
  /// Throws [StateError] if Bob's signature fails verification.
  InitiatorSessionResult finalizeSession({
    required String identityA,
    required String identityB,
    required LongTermPublicKey lpkA,
    required LongTermPublicKey lpkB,
    required LongTermSecretKey lskA,
    required EphemeralPreKey preKey,
    required KeyExchangeMessage message,
    required Uint8List seed,
  }) {
    // 1. Decapsulate both KEM ciphertexts
    final k = crypto.kem.decap(lskA.decapsulationKey, message.ciphertext);
    final kt = crypto.kem.decap(
      preKey.ephemeralSecretKey,
      message.ephemeralCiphertext,
    );

    // 2. Extract uniform keys
    final k1 = crypto.ext.extract(seed, k);
    final k2 = crypto.ext.extract(seed, kt);

    // 3. Build session ID
    final sid = SessionId.build(
      identityA: identityA,
      identityB: identityB,
      lpkA: lpkA,
      lpkB: lpkB,
      ephemeralPublicKey: preKey.ephemeralPublicKey,
      ciphertext: message.ciphertext,
      ephemeralCiphertext: message.ephemeralCiphertext,
    );

    // 4. PRF output: kA || k_tilde = F_K1(sid) XOR F_K2(sid)
    final outputLen = crypto.kem.level.prfOutputSize;
    final prfOut1 = crypto.prf.evaluate(k1, sid.data, outputLen);
    final prfOut2 = crypto.prf.evaluate(k2, sid.data, outputLen);

    final combined = Uint8List(outputLen);
    for (var i = 0; i < outputLen; i++) {
      combined[i] = prfOut1[i] ^ prfOut2[i];
    }

    final sessionKeySize = crypto.kem.level.sessionKeySize;
    final kA = Uint8List.fromList(
      Uint8List.sublistView(combined, 0, sessionKeySize),
    );
    final kTilde = Uint8List.sublistView(combined, sessionKeySize);

    // 5. Decrypt signature: sigma = c XOR k_tilde
    final sigma = Uint8List(message.encryptedSignature.length);
    for (var i = 0; i < sigma.length; i++) {
      sigma[i] = message.encryptedSignature[i] ^ kTilde[i];
    }

    // 6. Verify Bob's signature on sid
    if (!crypto.sig.verify(lpkB.verificationKey, sid.data, sigma)) {
      throw StateError(
        'Session finalization failed: invalid signature from responder',
      );
    }

    return InitiatorSessionResult(sessionKey: kA, sessionId: sid);
  }
}
