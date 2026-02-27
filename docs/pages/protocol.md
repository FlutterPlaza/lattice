# Protocol Specification

Lattice implements the post-quantum Signal handshake protocols described in Hashimoto et al. (PQC 2022). This page covers the SC-AKE (Strongly Compromised Authenticated Key Exchange) protocol in detail. For the deniable variant (SC-DAKE), see the [Ring Protocol](#ring-protocol) page.

## Overview

The classical Signal protocol uses X3DH for key agreement, which relies on elliptic-curve Diffie-Hellman and is vulnerable to quantum attacks. Lattice replaces X3DH with a generic construction based on:

- **KEM** (Key Encapsulation Mechanism) -- for establishing shared secrets
- **SIG** (Digital Signatures) -- for authentication
- **PRF** (Pseudorandom Function) -- for key derivation
- **Ext** (Randomness Extractor) -- for extracting uniform keys from KEM outputs

When instantiated with lattice-based primitives (ML-KEM and ML-DSA), the protocol achieves post-quantum security.

## Building Blocks

### KEM (Key Encapsulation Mechanism)

The KEM provides IND-CCA2 key encapsulation. Lattice uses ML-KEM (CRYSTALS-Kyber):

| Operation | Description |
|-----------|-------------|
| `KEM.KeyGen()` | Generates a key pair `(ek, dk)` -- encapsulation key and decapsulation key |
| `KEM.Encap(ek)` | Encapsulates a shared secret under `ek`, returns `(K, C)` -- shared secret and ciphertext |
| `KEM.Decap(dk, C)` | Decapsulates ciphertext `C` using `dk`, returns shared secret `K` |

### SIG (Digital Signatures)

The SIG provides EUF-CMA signatures. Lattice uses ML-DSA (CRYSTALS-Dilithium):

| Operation | Description |
|-----------|-------------|
| `SIG.KeyGen()` | Generates a key pair `(vk, sk)` -- verification key and signing key |
| `SIG.Sign(sk, m)` | Signs message `m` with `sk`, returns signature `sigma` |
| `SIG.Verify(vk, m, sigma)` | Verifies signature `sigma` on `m` under `vk`, returns `true/false` |

### PRF (Pseudorandom Function)

The PRF uses HMAC-SHA256 with counter-mode expansion (HKDF-Expand style):

```
T(1) = HMAC(key, 0x01 || sid || 0x01)
T(i) = HMAC(key, T(i-1) || 0x01 || sid || i)
output = T(1) || T(2) || ... truncated to desired length
```

This produces up to 8160 bytes of pseudorandom output.

### Ext (Randomness Extractor)

The Ext uses HMAC-SHA256 as a strong randomness extractor:

```
Ext_s(K) = HMAC-SHA256(s, 0x02 || K)
```

where `s` is a 32-byte seed and `K` is the input keying material from a KEM shared secret.

## Security Levels

Lattice supports three NIST security levels:

| Level | Bits | KEM | SIG | KEM Public Key | KEM Ciphertext | SIG Signature |
|-------|------|-----|-----|----------------|----------------|---------------|
| L128 | 128 | ML-KEM-512 | ML-DSA-44 | 800 B | 768 B | 2420 B |
| L192 | 192 | ML-KEM-768 | ML-DSA-65 | 1184 B | 1088 B | 3309 B |
| L256 | 256 | ML-KEM-1024 | ML-DSA-87 | 1568 B | 1568 B | 4627 B |

The default security level is **L192** (NIST Level 3, 192-bit security).

## Key Types

### Long-Term Keys

Each user generates a long-term key pair during registration:

- **Long-term public key `lpk = (ek, vk)`** -- KEM encapsulation key + SIG verification key
- **Long-term secret key `lsk = (dk, sk)`** -- KEM decapsulation key + SIG signing key

### Ephemeral Pre-Keys

To enable asynchronous session establishment, Alice uploads signed ephemeral pre-keys to the server:

- **Ephemeral key pair `(ekT, dkT)`** -- a one-time KEM key pair (ek-tilde, dk-tilde)
- **Pre-key signature `sigma_A = SIG.Sign(sk_A, ekT)`** -- proves Alice generated this pre-key

The server stores the **pre-key bundle** `(lpk_A, ekT, sigma_A)` for distribution to peers.

## Registration Flow

```
Alice                                Server
  |                                    |
  |-- Generate: KEM.KeyGen -> (ek,dk) |
  |-- Generate: SIG.KeyGen -> (vk,sk) |
  |                                    |
  |-- POST /api/v1/register           |
  |   {userId, publicKey: lpk}  ------>|
  |                                    |-- Store lpk
  |<------ 201 Created ---------------|
```

## Session Establishment Flow

The protocol has two phases: Alice uploads a pre-key (offline), then Bob creates a session using that pre-key.

![Protocol Flow](assets/protocol-flow.svg)

### Phase 1: Alice Uploads a Pre-Key

```
Alice                                Server
  |                                    |
  |-- wKEM.KeyGen -> (ekT, dkT)      |
  |-- SIG.Sign(skA, ekT) -> sigma_A  |
  |                                    |
  |-- POST /api/v1/prekeys            |
  |   {userId, bundle: (lpkA,ekT,sigmaA)} ->|
  |                                    |-- Store bundle
  |<------ 200 OK -------------------|
```

### Phase 2: Bob Creates a Session

Bob fetches Alice's pre-key bundle and performs the handshake:

```
Bob                                  Server                  Alice
  |                                    |                       |
  |-- GET /api/v1/prekeys/alice ------>|                       |
  |<----- {bundle: (lpkA,ekT,sigmaA)}-|                       |
  |                                    |                       |
  | 1. SIG.Verify(vkA, ekT, sigmaA)   |                       |
  | 2. (K, C)  <- KEM.Encap(ekA)      |                       |
  |    (KT,CT) <- wKEM.Encap(ekT)     |                       |
  | 3. K1 <- Ext_s(K)                 |                       |
  |    K2 <- Ext_s(KT)                |                       |
  | 4. sid := A||B||lpkA||lpkB||ekT||C||CT                    |
  | 5. kB||k_tilde <- F_K1(sid) XOR F_K2(sid)                 |
  | 6. sigma <- SIG.Sign(skB, sid)    |                       |
  |    c <- sigma XOR k_tilde         |                       |
  |                                    |                       |
  |-- POST /api/v1/messages/alice ---->|                       |
  |   {senderId:bob, message:(C,CT,c)} |                       |
  |                                    |                       |
  |                                    |   (Alice comes online)|
  |                                    |<-- GET messages/alice -|
  |                                    |--- {messages: [...]} ->|
  |                                    |                       |
  |                                    | 1. K  <- KEM.Decap(dkA, C)
  |                                    | 2. KT <- wKEM.Decap(dkT, CT)
  |                                    | 3. K1 <- Ext_s(K)
  |                                    |    K2 <- Ext_s(KT)
  |                                    | 4. sid := A||B||lpkA||lpkB||ekT||C||CT
  |                                    | 5. kA||k_tilde <- F_K1(sid) XOR F_K2(sid)
  |                                    | 6. sigma <- c XOR k_tilde
  |                                    |    SIG.Verify(vkB, sid, sigma)
  |                                    |                       |
  |         kB == kA (shared session key established)          |
```

## Session ID Construction

The session identifier `sid` is a length-prefixed concatenation of all public handshake data:

```
sid = [A] || [B] || [lpkA] || [lpkB] || [ekT] || [C] || [CT]
```

Each component is encoded with a 4-byte big-endian length prefix to ensure unambiguous parsing. This binds the session key to the complete handshake transcript.

## Security Properties

The SC-AKE protocol provides the following security guarantees:

### IND-CCA Security (KEM)
The key encapsulation mechanism is secure against adaptive chosen-ciphertext attacks, meaning an attacker who can query the decapsulation oracle cannot distinguish real shared secrets from random.

### EUF-CMA Security (SIG)
The signature scheme is existentially unforgeable under chosen-message attacks, meaning an attacker who can query the signing oracle cannot produce a valid signature on a new message.

### State Leakage Security
Even if an adversary compromises a user's ephemeral pre-key secret `dkT` (but not the long-term key `dk`), the protocol remains secure. The session key depends on both the long-term KEM ciphertext `C` and the ephemeral ciphertext `CT`, so compromising only one does not reveal the session key.

### Key Derivation
The XOR of two independent PRF outputs ensures that the session key is uniform even if one of the two KEM shared secrets is compromised. The randomness extractor `Ext` converts potentially biased KEM outputs into uniform keys before PRF evaluation.

## Citation

```bibtex
@inproceedings{hashimoto2022efficient,
  title={An Efficient and Generic Construction for Signal's Handshake (X3DH):
         Post-Quantum, State Leakage Secure, and Deniable},
  author={Hashimoto, Keitaro and Katsumata, Shuichi and
          Kwiatkowski, Kris and Prest, Thomas},
  booktitle={Post-Quantum Cryptography},
  year={2022},
  publisher={Springer},
  doi={10.1007/978-3-031-17234-2_2}
}
```
