# Security

This page describes the security model of the Lattice post-quantum Signal protocol implementation, including the cryptographic guarantees, threat model, and operational best practices.

## Security Model

Lattice provides authenticated key exchange (AKE) between two parties, Alice and Bob, mediated by an untrusted key distribution server. The protocol guarantees:

1. **Key agreement** -- Both parties derive the same session key `k` at the end of a successful handshake.
2. **Authentication** -- Each party is assured that the other party holds the corresponding long-term secret key. An active attacker cannot impersonate either party without their long-term key.
3. **Session key secrecy** -- A passive eavesdropper (even a quantum adversary) cannot recover the session key from the handshake transcript.

## Post-Quantum Security

Lattice replaces all Diffie-Hellman-based operations in the classical Signal protocol with lattice-based cryptography:

| Classical Signal | Lattice |
|-----------------|---------|
| X25519 DH | ML-KEM (Kyber) key encapsulation |
| Ed25519 signatures | ML-DSA (Dilithium) signatures |
| HKDF | HMAC-SHA256 based PRF + Ext |

The underlying hard problems (Module-LWE for KEM, Module-SIS for SIG) are believed to be intractable for both classical and quantum computers.

### NIST Standards Compliance

Lattice uses the NIST-standardized post-quantum algorithms:

- **FIPS 203** (ML-KEM) -- Module-Lattice-Based Key-Encapsulation Mechanism
- **FIPS 204** (ML-DSA) -- Module-Lattice-Based Digital Signature Algorithm

The default security level (L192) targets NIST Level 3, equivalent to 192-bit classical security.

## State Leakage Security

A distinctive feature of the Lattice protocol is **state leakage security** (SC-AKE). Even if an adversary compromises a user's ephemeral pre-key decapsulation key `dkT`, the session key remains secure as long as the long-term decapsulation key `dk` is uncompromised.

This is achieved by deriving the session key from **two independent** KEM shared secrets:

```
K1 = Ext_s(KEM.Decap(dk, C))       -- long-term key
K2 = Ext_s(wKEM.Decap(dkT, CT))    -- ephemeral key

session_key = F_K1(sid) XOR F_K2(sid)
```

An attacker must compromise **both** `dk` and `dkT` to recover the session key. Compromising only the ephemeral state (`dkT`) is insufficient.

## Key Management Best Practices

### Long-Term Keys

- Generate long-term keys using a cryptographically secure random number generator (`Random.secure()` in Dart).
- Store long-term secret keys in platform-specific secure storage (iOS Keychain, Android Keystore, OS credential manager). **Never** store secret keys in plain files or shared preferences.
- Implement key rotation on a regular schedule or when compromise is suspected.
- Zero key material from memory when no longer needed (see "Key Zeroing" below).

### Ephemeral Pre-Keys

- Pre-keys are single-use. Upload a fresh pre-key after each session is established.
- The server deletes a pre-key after it is fetched. If session finalization fails, the pre-key is consumed and a new one must be uploaded.
- Store the ephemeral secret key `dkT` locally until the session is finalized, then delete it.

### Session Keys

- Session keys are derived from the handshake and should be used for a limited time or number of messages.
- Implement session ratcheting (Double Ratchet) for ongoing conversations. The SC-AKE handshake establishes the initial session key; subsequent messages should use forward-secure ratcheting.
- Delete session keys when the session is closed.

## What is NOT Logged

The server's logging middleware is designed to **never** expose cryptographic material:

- Request and response **bodies** are never logged (they contain base64-encoded keys and ciphertexts).
- Only the HTTP method, request path, response status code, and request duration are logged.
- Error messages returned to clients never include internal exception details in production.

Example log line:

```
2024-01-15T10:30:00.000Z POST /api/v1/register -> 201 (12ms)
```

## Constant-Time Operations

Critical operations in the cryptographic layer use constant-time algorithms to prevent timing side-channel attacks:

- KEM decapsulation performs the same operations regardless of whether the ciphertext is valid.
- Signature verification processes the entire signature before returning a result.
- Byte comparison operations use constant-time equality checks.

> **Note:** The current pure-Dart reference implementation prioritizes correctness over constant-time guarantees. When native FFI bindings for ML-KEM and ML-DSA become available, they will provide hardware-level constant-time operations.

## Key Zeroing

After a key or secret value is no longer needed, it should be overwritten with zeros to prevent recovery from memory:

```dart
// Overwrite a Uint8List with zeros
void zeroKey(Uint8List key) {
  for (var i = 0; i < key.length; i++) {
    key[i] = 0;
  }
}
```

Apply key zeroing to:

- Long-term secret keys when rotating to new keys
- Ephemeral pre-key secrets after session finalization
- Session keys when the session is closed
- PRF and Ext intermediate values after use

> **Caveat:** Dart's garbage collector may copy objects in memory, making true zeroing difficult to guarantee. For the strongest guarantees, use FFI to allocate and manage secret keys in native memory.

## TLS Enforcement

All client-server communication should use TLS 1.3 in production:

- Terminate TLS at a reverse proxy (nginx, Caddy, cloud load balancer).
- Use certificates from a trusted CA.
- Configure HSTS headers.
- The `Connection` class accepts any HTTPS URL -- ensure your base URL uses `https://` in production.

Without TLS, an active network attacker can:

- Read pre-key bundles and key-exchange messages (though they cannot derive session keys without long-term keys).
- Modify messages in transit, causing handshake failures.
- Perform denial-of-service by dropping messages.

## Rate Limiting

The server includes per-IP rate limiting middleware:

```dart
Middleware.rateLimit(
  maxRequests: 100,
  window: Duration(minutes: 1),
)
```

This limits each IP to 100 requests per minute. Exceeding the limit returns HTTP 429.

**When to enable:** Rate limiting is not enabled in the default middleware pipeline. Enable it for internet-facing deployments to mitigate brute-force registration and pre-key exhaustion attacks.

### Pre-Key Exhaustion Attack

An attacker could repeatedly fetch a victim's pre-key to exhaust their supply, preventing legitimate peers from establishing sessions. Mitigations:

1. Enable rate limiting.
2. Require authentication (Bearer token) for pre-key fetch requests.
3. Monitor the pre-key count and alert when it drops to zero.
4. Implement pre-key batching (upload multiple pre-keys; the server distributes them one at a time).

## Threat Model Summary

| Threat | Protected | Notes |
|--------|-----------|-------|
| Passive quantum eavesdropper | Yes | Lattice-based KEM + SIG |
| Active MITM (no key compromise) | Yes | Mutual authentication via SIG |
| Ephemeral state compromise (`dkT`) | Yes | State leakage security (SC-AKE) |
| Long-term key compromise (`dk` + `sk`) | No | Full impersonation possible |
| Server compromise | Partial | Server cannot derive session keys, but can deny service or delete data |
| Side-channel timing attack | Partial | Reference implementation; use native FFI for strong guarantees |
| Memory forensics | Partial | Key zeroing helps, but Dart GC may leave copies |
