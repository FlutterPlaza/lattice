# Client Usage

The `lattice_client` package provides a high-level `LatticeClient` API that orchestrates the full lifecycle of the post-quantum Signal handshake: registration, pre-key management, session initiation, and session finalization.

## Overview

The client coordinates four components:

- **Connection** -- HTTP client for the Lattice server REST API
- **SecureStorage** -- local persistence for long-term keys and pre-keys
- **CryptoProvider** -- cryptographic primitives (KEM, SIG, PRF, Ext)
- **SessionManager** -- in-memory manager for established sessions

## Creating a Client

```dart
import 'package:lattice_client/lattice_client.dart';

final client = LatticeClient(
  userId: 'alice',
  connection: Connection(baseUrl: 'http://localhost:8080'),
);
```

### Constructor Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `userId` | `String` | Yes | -- | Local user's identity string |
| `connection` | `Connection` | Yes | -- | Server connection layer |
| `storage` | `SecureStorage` | No | `InMemorySecureStorage` | Key persistence backend |
| `crypto` | `CryptoProvider` | No | `CryptoProvider()` (L192) | Cryptographic primitives |

## Registration

Registration generates a long-term key pair (KEM + SIG), stores it locally, and registers the public key with the server:

```dart
await client.register();
```

This executes:

1. `KEM.KeyGen()` to produce `(ek, dk)`
2. `SIG.KeyGen()` to produce `(vk, sk)`
3. Local storage of `lpk = (ek, vk)` and `lsk = (dk, sk)`
4. `POST /api/v1/register` with the serialized `lpk`

## Pre-Key Management

Upload a signed ephemeral pre-key to the server so that peers can initiate sessions asynchronously:

```dart
await client.uploadPreKey();
```

This executes:

1. `wKEM.KeyGen()` to produce `(ekT, dkT)` -- the ephemeral key pair
2. `SIG.Sign(sk, ekT)` to produce `sigma` -- proves the pre-key belongs to this user
3. Local storage of the full `EphemeralPreKey` (including secret `dkT`)
4. `POST /api/v1/prekeys` with the `PreKeyBundle` (public components only)

> **Important:** Pre-keys are one-time use. The server removes the pre-key after it is fetched by a peer. You should upload a fresh pre-key before each expected session.

## Session Initiation (Responder / Bob Side)

Initiate a session with a peer by fetching their pre-key bundle and performing the responder side of the SC-AKE handshake:

```dart
final session = await client.initiateSession('alice');
print('Session key: ${session.sessionKey}');
print('Peer: ${session.remoteIdentity}');
```

This executes:

1. `GET /api/v1/prekeys/alice` to fetch Alice's pre-key bundle
2. Verify Alice's pre-key signature: `SIG.Verify(vkA, ekT, sigmaA)`
3. Encapsulate two shared secrets: `(K, C) = KEM.Encap(ekA)` and `(KT, CT) = wKEM.Encap(ekT)`
4. Extract uniform keys: `K1 = Ext_s(K)`, `K2 = Ext_s(KT)`
5. Build session ID: `sid = A || B || lpkA || lpkB || ekT || C || CT`
6. Derive session key: `kB || k_tilde = F_K1(sid) XOR F_K2(sid)`
7. Sign and encrypt: `sigma = SIG.Sign(skB, sid)`, `c = sigma XOR k_tilde`
8. `POST /api/v1/messages/alice` with the key-exchange message `(C, CT, c)` plus the seed

The returned `Session` object contains the session key, session ID, and peer identity.

## Session Finalization (Initiator / Alice Side)

Process pending key-exchange messages and finalize sessions as the initiator (Alice):

```dart
final sessions = await client.respondToSessions();
for (final session in sessions) {
  print('Session with ${session.remoteIdentity} established');
}
```

This executes:

1. `GET /api/v1/messages/alice` to fetch pending messages
2. For each message, decode the payload (seed + sender lpk + key-exchange message)
3. Decapsulate: `K = KEM.Decap(dkA, C)`, `KT = wKEM.Decap(dkT, CT)`
4. Extract, derive, and verify (mirror of the responder steps)
5. If all verifications pass, the session key `kA` matches `kB`
6. Consume the local pre-key after processing

> The pre-key is removed from local storage after processing messages. Upload a new pre-key before the next expected session.

## Session Manager

Active sessions are tracked by the `SessionManager`:

```dart
// Check if a session exists
if (client.sessions.hasSession('bob')) {
  final session = client.sessions.getSession('bob');
  // Use session.sessionKey for encryption...
}

// List all active sessions
for (final s in client.sessions.activeSessions) {
  print('${s.localIdentity} <-> ${s.remoteIdentity}');
}

// Remove a session
client.sessions.removeSession('bob');
```

## Secure Storage

The `SecureStorage` abstract class defines the interface for key persistence:

| Method | Description |
|--------|-------------|
| `saveIdentity(userId, publicKey, secretKey)` | Store long-term key pair |
| `getPublicKey(userId)` | Retrieve long-term public key |
| `getSecretKey(userId)` | Retrieve long-term secret key |
| `savePreKey(userId, preKey)` | Store ephemeral pre-key |
| `getPreKey(userId)` | Retrieve ephemeral pre-key |
| `removePreKey(userId)` | Delete ephemeral pre-key |
| `clear()` | Remove all stored keys |

### InMemorySecureStorage

The default implementation stores keys in Dart `Map` objects. Data is lost when the process exits. **Do not use in production.**

### Custom Implementation

For production, implement `SecureStorage` using a platform-specific secure storage backend:

```dart
class KeychainSecureStorage implements SecureStorage {
  // iOS: Keychain Services
  // Android: Android Keystore
  // Desktop: OS-specific credential storage
  // ...
}
```

## Connection

The `Connection` class handles HTTP communication with the server:

```dart
final conn = Connection(baseUrl: 'http://localhost:8080');

// Optional: set a Bearer token for authenticated requests
conn.setAuthToken('my-secret-token');

// Health check
final health = await conn.health();
print('Server status: ${health['status']}');

// Cleanup
conn.close();
```

## Complete Example

```dart
import 'package:lattice_client/lattice_client.dart';

Future<void> main() async {
  final serverUrl = 'http://localhost:8080';

  // Create clients
  final alice = LatticeClient(
    userId: 'alice',
    connection: Connection(baseUrl: serverUrl),
  );
  final bob = LatticeClient(
    userId: 'bob',
    connection: Connection(baseUrl: serverUrl),
  );

  // Register both users
  await alice.register();
  await bob.register();

  // Alice uploads a pre-key (she can go offline after this)
  await alice.uploadPreKey();

  // Bob initiates a session with Alice
  final bobSession = await bob.initiateSession('alice');
  print('Bob session key length: ${bobSession.sessionKey.length} bytes');

  // Alice comes online and finalizes the session
  final aliceSessions = await alice.respondToSessions();
  final aliceSession = aliceSessions.first;
  print('Alice session key length: ${aliceSession.sessionKey.length} bytes');

  // Both session keys are identical
  print('Keys match: ${_keysEqual(
    bobSession.sessionKey,
    aliceSession.sessionKey,
  )}');

  // Cleanup
  alice.close();
  bob.close();
}

bool _keysEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

## Error Handling

The client throws the following exceptions:

| Exception | When |
|-----------|------|
| `StateError('Must register before uploading pre-keys')` | `uploadPreKey()` called before `register()` |
| `StateError('No pre-key available for ...')` | `initiateSession()` when the peer has no pre-key on the server |
| `StateError('Not registered')` | Any operation requiring registration when not registered |
| `StateError('No pre-key available')` | `respondToSessions()` when the local pre-key has not been uploaded |
| `StateError('Session finalization failed: invalid signature from responder')` | The responder's signature does not verify -- possible tampering |
| `LatticeApiException(statusCode, message)` | Server returned a non-success HTTP status |

## Lifecycle

Always call `close()` when the client is no longer needed:

```dart
client.close();
```

This closes the underlying HTTP client. The session manager and stored keys remain accessible until the object is garbage collected.
