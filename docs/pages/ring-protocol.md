# Ring Protocol (SC-DAKE)

The SC-DAKE (Strongly Compromised Deniable Authenticated Key Exchange) variant of the Lattice protocol adds **deniability** to the handshake by replacing standard digital signatures with ring signatures. This page covers the motivation, construction, and usage of the ring protocol.

## Overview

In the standard SC-AKE protocol, Bob signs the session ID with his long-term signing key `sk_B`. Alice can use this signature to prove to a third party that Bob participated in the handshake. This is a problem in scenarios where deniability is desired -- for example, if Bob wants to deny having communicated with Alice.

SC-DAKE replaces Bob's standard signature with a **ring signature** over a 2-member ring `{vk_A, vk_B}`. A ring signature proves that the signer is one of the two members of the ring, but does not reveal which one. This means:

- Alice can verify that the signature came from either herself or Bob.
- Since Alice knows she did not sign, she concludes Bob must have signed.
- A third party cannot distinguish whether Alice or Bob signed, so Alice cannot prove to a third party that Bob participated.

## Deniability Property

Deniability means that after a handshake completes, neither party can produce a transcript that convinces a third party of the other's involvement. Specifically:

- **Bob's deniability:** Alice cannot prove that Bob signed the session ID, because the ring signature could have been produced by either Alice or Bob.
- **Transcript simulation:** Alice could simulate the entire transcript (including the ring signature) by herself, using her own signing key as the ring member who signs.

This property is important for privacy-sensitive applications where participants may need to deny having communicated.

## Ring Signature Construction

### Interface

The `RingSig` abstract class in `lattice_crypto` defines the ring signature interface:

```dart
abstract class RingSig {
  SecurityLevel get level;

  /// Generate a key pair compatible with ring signing.
  SigKeyPair keyGen();

  /// Sign [message] as a member of [ring] using [signingKey].
  /// The signer's verification key must be present in [ring].
  Uint8List ringSign(
    Uint8List signingKey,
    Uint8List message,
    List<Uint8List> ring,
  );

  /// Verify that [signature] is valid for [message] under [ring].
  bool ringVerify(
    Uint8List message,
    Uint8List signature,
    List<Uint8List> ring,
  );
}
```

### 2-Member Ring: {vk_A, vk_B}

In the SC-DAKE protocol, the ring always contains exactly two verification keys:

```
ring = [vk_A, vk_B]
```

Bob signs with his `sk_B` within this ring. The resulting signature proves:

1. The signer knows the secret key corresponding to one of `{vk_A, vk_B}`.
2. It is computationally infeasible to determine which key was used.

### Construction Details

The `RingSigPure` implementation uses a lattice-based ring signature scheme. The key generation reuses the same key type as `Sig` (ML-DSA key pairs), so a user's existing long-term signing key pair `(vk, sk)` can be used directly for ring signing.

The ring signature is constructed as follows:

1. For each non-signer in the ring, generate a simulated signature response using random values.
2. For the actual signer, compute the real signature that makes the ring equation balance.
3. The final signature includes all responses and a challenge hash, in a canonical order that does not reveal the signer's position.

## Protocol Flow: SC-DAKE vs SC-AKE

The SC-DAKE protocol is identical to SC-AKE except in steps 6-7 of Bob's flow:

### SC-AKE (standard)

```
6. sigma <- SIG.Sign(skB, sid)
7. c <- sigma XOR k_tilde
```

### SC-DAKE (deniable)

```
6. sigma <- RingSig.RingSign(skB, sid, [vkA, vkB])
7. c <- sigma XOR k_tilde
```

On Alice's side, verification changes accordingly:

### SC-AKE (standard)

```
6. sigma <- c XOR k_tilde
7. SIG.Verify(vkB, sid, sigma)
```

### SC-DAKE (deniable)

```
6. sigma <- c XOR k_tilde
7. RingSig.RingVerify(sid, sigma, [vkA, vkB])
```

## When to Use SC-DAKE vs SC-AKE

| Property | SC-AKE | SC-DAKE |
|----------|--------|---------|
| Authentication | Yes | Yes |
| Post-quantum security | Yes | Yes |
| State leakage security | Yes | Yes |
| Deniability | No | Yes |
| Signature size | Smaller (standard SIG) | Larger (ring SIG for 2 members) |
| Verification speed | Faster | Slower |

**Use SC-AKE when:**

- Non-repudiation is desirable (e.g., financial transactions, legal communications).
- Signature size and verification speed are critical.
- Deniability is not a requirement.

**Use SC-DAKE when:**

- Privacy and deniability are important (e.g., private messaging, whistleblower communications).
- Participants may need to deny having communicated.
- The overhead of ring signatures is acceptable.

## Implementation Details

### CryptoProvider Access

Both `Sig` and `RingSig` are available through the `CryptoProvider`:

```dart
final crypto = CryptoProvider(level: SecurityLevel.l192);

// Standard signature
final sig = crypto.sig;

// Ring signature
final ringSig = crypto.ringSig;
```

### Key Compatibility

Ring signature keys are type-compatible with standard signature keys (`SigKeyPair`). A user's existing long-term key pair can be used for both SC-AKE and SC-DAKE handshakes:

```dart
// Generate keys (same type for both)
final keyPair = crypto.sig.keyGen();
// OR
final keyPair = crypto.ringSig.keyGen();

// Both produce SigKeyPair with verificationKey and signingKey
```

### Example: Ring Sign and Verify

```dart
final crypto = CryptoProvider();

// Alice and Bob's key pairs
final aliceKeys = crypto.ringSig.keyGen();
final bobKeys = crypto.ringSig.keyGen();

// The ring: both verification keys
final ring = [aliceKeys.verificationKey, bobKeys.verificationKey];

// Bob signs a message within the ring
final message = Uint8List.fromList(utf8.encode('session-id-data'));
final signature = crypto.ringSig.ringSign(bobKeys.signingKey, message, ring);

// Anyone can verify the signature came from a ring member
final valid = crypto.ringSig.ringVerify(message, signature, ring);
print('Valid: $valid'); // true

// But no one can determine whether Alice or Bob signed
```

## Security Considerations

- The ring signature provides **computational** deniability, not information-theoretic deniability. An adversary with unbounded computational power could potentially distinguish the signer.
- In a 2-member ring, both parties know their own key, so each can determine who signed by elimination. The deniability is against **third parties** who do not know either secret key.
- Ring signature sizes scale with the ring size. For the 2-member ring used in SC-DAKE, the overhead compared to a standard signature is approximately 2x.

## Paper Reference

The SC-DAKE construction is described in Section 5 of:

> Hashimoto, K., Katsumata, S., Kwiatkowski, K., & Prest, T. (2022). "An Efficient and Generic Construction for Signal's Handshake (X3DH): Post-Quantum, State Leakage Secure, and Deniable." *Post-Quantum Cryptography (PQC 2022)*, Springer.
