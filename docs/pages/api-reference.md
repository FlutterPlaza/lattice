# API Reference

This page provides the complete reference for the Lattice server REST API and the client SDK Dart API.

---

## Server REST API

All endpoints use JSON request and response bodies. Cryptographic material is encoded as base64 strings. The base path for all endpoints is `/api/v1`.

### POST /api/v1/register

Registers a new user with their serialized long-term public key.

**Request:**

```json
{
  "userId": "alice",
  "publicKey": "<base64-encoded LongTermPublicKey>"
}
```

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 201 | `{"status": "registered", "userId": "alice"}` | User registered successfully |
| 400 | `{"error": "Missing or empty userId"}` | Invalid request body |
| 400 | `{"error": "Missing or empty publicKey"}` | Invalid request body |
| 409 | `{"error": "User \"alice\" already registered"}` | User ID already taken |

---

### POST /api/v1/prekeys

Uploads (or replaces) a signed pre-key bundle for a user.

**Request:**

```json
{
  "userId": "alice",
  "bundle": "<base64-encoded PreKeyBundle>"
}
```

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | `{"status": "stored", "userId": "alice"}` | Bundle stored successfully |
| 400 | `{"error": "Missing or empty userId"}` | Invalid request body |
| 400 | `{"error": "Missing or empty bundle"}` | Invalid request body |

---

### GET /api/v1/prekeys/:userId

Fetches and removes the pre-key bundle for a user. The bundle is consumed on retrieval (one-time use).

**Parameters:**

| Parameter | Location | Description |
|-----------|----------|-------------|
| `userId` | URL path | The user whose pre-key to fetch |

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | `{"userId": "alice", "bundle": "<base64>"}` | Bundle retrieved and removed |
| 404 | `{"error": "No pre-key bundle for user \"alice\""}` | No bundle available |

---

### POST /api/v1/messages/:userId

Sends a key-exchange message to the specified user. Messages are stored until the recipient fetches them.

**Parameters:**

| Parameter | Location | Description |
|-----------|----------|-------------|
| `userId` | URL path | The recipient user ID |

**Request:**

```json
{
  "senderId": "bob",
  "message": "<base64-encoded payload>"
}
```

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | `{"status": "delivered"}` | Message queued for delivery |
| 400 | `{"error": "Missing or empty senderId"}` | Invalid request body |
| 400 | `{"error": "Missing or empty message"}` | Invalid request body |

---

### GET /api/v1/messages/:userId

Fetches and clears all pending messages for the specified user.

**Parameters:**

| Parameter | Location | Description |
|-----------|----------|-------------|
| `userId` | URL path | The user whose messages to fetch |

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | See below | Messages retrieved and cleared |

**Response body:**

```json
{
  "messages": [
    {
      "senderId": "bob",
      "message": "<base64-encoded payload>",
      "sentAt": "2024-01-15T10:30:00.000Z"
    }
  ]
}
```

The `messages` array is empty if no messages are pending.

---

### GET /api/v1/health

Returns server health status.

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | See below | Server is healthy |

**Response body:**

```json
{
  "status": "ok",
  "uptime": 3600,
  "version": "0.1.0"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | String | Always `"ok"` |
| `uptime` | int | Server uptime in seconds |
| `version` | String | Server version string |

---

### GET /api/v1/metrics

Returns operational metrics. Never exposes cryptographic material.

**Responses:**

| Status | Body | Description |
|--------|------|-------------|
| 200 | See below | Metrics retrieved |

**Response body:**

```json
{
  "users": 42,
  "prekeys": 15,
  "pendingMessages": 3,
  "uptime": 7200
}
```

| Field | Type | Description |
|-------|------|-------------|
| `users` | int | Total registered users |
| `prekeys` | int | Currently stored pre-key bundles |
| `pendingMessages` | int | Total pending key-exchange messages |
| `uptime` | int | Server uptime in seconds |

---

### Error Codes

| HTTP Status | Meaning | When |
|-------------|---------|------|
| 400 | Bad Request | Malformed JSON, missing required fields |
| 401 | Unauthorized | Missing or invalid Bearer token (when auth middleware is enabled) |
| 404 | Not Found | Requested resource does not exist |
| 409 | Conflict | Duplicate registration |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected server error |

All error responses follow this format:

```json
{
  "error": "Human-readable error message"
}
```

---

## Client SDK API

### LatticeClient

The main entry point for the Lattice protocol.

```dart
class LatticeClient {
  LatticeClient({
    required String userId,
    required Connection connection,
    SecureStorage? storage,
    CryptoProvider? crypto,
  });

  final String userId;
  final Connection connection;
  final SecureStorage storage;
  final CryptoProvider crypto;
  final SessionManager sessions;

  Future<void> register();
  Future<void> uploadPreKey();
  Future<Session> initiateSession(String peerId);
  Future<List<Session>> respondToSessions();
  void close();
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `register()` | `Future<void>` | Generate long-term keys and register with the server |
| `uploadPreKey()` | `Future<void>` | Generate and upload a signed ephemeral pre-key |
| `initiateSession(peerId)` | `Future<Session>` | Initiate a session with a peer (Bob side of SC-AKE) |
| `respondToSessions()` | `Future<List<Session>>` | Finalize pending sessions (Alice side of SC-AKE) |
| `close()` | `void` | Close the HTTP connection |

---

### Connection

HTTP client for the Lattice server.

```dart
class Connection {
  Connection({required String baseUrl, http.Client? client});

  void setAuthToken(String token);
  Future<void> register(String userId, Uint8List publicKeyData);
  Future<void> uploadPreKey(String userId, Uint8List bundleData);
  Future<Uint8List?> fetchPreKey(String userId);
  Future<void> sendMessage(String recipientId, String senderId, Uint8List messageData);
  Future<List<({String senderId, Uint8List messageData})>> fetchMessages(String userId);
  Future<Map<String, dynamic>> health();
  void close();
}
```

| Method | Description |
|--------|-------------|
| `setAuthToken(token)` | Set the Bearer token for authenticated requests |
| `register(userId, publicKeyData)` | Register a user with the server |
| `uploadPreKey(userId, bundleData)` | Upload a serialized pre-key bundle |
| `fetchPreKey(userId)` | Fetch and consume a pre-key bundle (returns `null` if 404) |
| `sendMessage(recipientId, senderId, messageData)` | Send a key-exchange message |
| `fetchMessages(userId)` | Fetch and clear pending messages |
| `health()` | Check server health |
| `close()` | Close the underlying HTTP client |

---

### CryptoProvider

Factory for cryptographic primitives at a given security level.

```dart
class CryptoProvider {
  const CryptoProvider({SecurityLevel level = SecurityLevel.l192});

  final SecurityLevel level;

  Kem get kem;        // Key Encapsulation Mechanism
  Sig get sig;        // Digital Signatures
  RingSig get ringSig; // Ring Signatures
  Prf get prf;        // Pseudorandom Function
  Ext get ext;        // Randomness Extractor
}
```

---

### Kem

Abstract Key Encapsulation Mechanism interface.

```dart
abstract class Kem {
  SecurityLevel get level;
  KemKeyPair keyGen();
  KemEncapsulation encap(Uint8List publicKey);
  Uint8List decap(Uint8List secretKey, Uint8List ciphertext);
}
```

| Type | Fields |
|------|--------|
| `KemKeyPair` | `Uint8List publicKey`, `Uint8List secretKey` |
| `KemEncapsulation` | `Uint8List ciphertext`, `Uint8List sharedSecret` |

---

### Sig

Abstract digital signature interface.

```dart
abstract class Sig {
  SecurityLevel get level;
  SigKeyPair keyGen();
  Uint8List sign(Uint8List signingKey, Uint8List message);
  bool verify(Uint8List verificationKey, Uint8List message, Uint8List signature);
}
```

| Type | Fields |
|------|--------|
| `SigKeyPair` | `Uint8List verificationKey`, `Uint8List signingKey` |

---

### RingSig

Abstract ring signature interface for SC-DAKE.

```dart
abstract class RingSig {
  SecurityLevel get level;
  SigKeyPair keyGen();
  Uint8List ringSign(Uint8List signingKey, Uint8List message, List<Uint8List> ring);
  bool ringVerify(Uint8List message, Uint8List signature, List<Uint8List> ring);
}
```

---

### Prf

Pseudorandom function (HMAC-SHA256 with counter-mode expansion).

```dart
class Prf {
  const Prf();
  Uint8List evaluate(Uint8List key, Uint8List sessionId, int outputLength);
}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `Uint8List` | PRF key (extracted KEM shared secret) |
| `sessionId` | `Uint8List` | Session identifier bytes |
| `outputLength` | `int` | Desired output length (1 to 8160 bytes) |

---

### Ext

Strong randomness extractor (HMAC-SHA256).

```dart
class Ext {
  const Ext();
  Uint8List extract(Uint8List seed, Uint8List input);
}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `seed` | `Uint8List` | 32-byte random seed |
| `input` | `Uint8List` | Input keying material (KEM shared secret) |
| **Returns** | `Uint8List` | 32-byte extracted key |

---

### SecurityLevel

Enumeration of NIST post-quantum security levels.

```dart
enum SecurityLevel {
  l128(128, 'ML-KEM-512',  'ML-DSA-44', 800,  1632, 768,  1312, 2420),
  l192(192, 'ML-KEM-768',  'ML-DSA-65', 1184, 2400, 1088, 1952, 3309),
  l256(256, 'ML-KEM-1024', 'ML-DSA-87', 1568, 3168, 1568, 2592, 4627);
}
```

| Property | Type | Description |
|----------|------|-------------|
| `bits` | `int` | Security strength in bits |
| `kemName` | `String` | KEM algorithm name |
| `sigName` | `String` | SIG algorithm name |
| `kemPublicKeySize` | `int` | KEM public key size in bytes |
| `kemSecretKeySize` | `int` | KEM secret key size in bytes |
| `kemCiphertextSize` | `int` | KEM ciphertext size in bytes |
| `sigPublicKeySize` | `int` | SIG verification key size in bytes |
| `sigSignatureSize` | `int` | SIG signature size in bytes |
| `sessionKeySize` | `int` | Derived session key size (`bits / 8`) |
| `prfOutputSize` | `int` | PRF output size (`sessionKeySize + sigSignatureSize`) |

---

### Protocol Types

#### LongTermPublicKey

```dart
class LongTermPublicKey {
  LongTermPublicKey({required Uint8List encapsulationKey, required Uint8List verificationKey});
  factory LongTermPublicKey.deserialize(Uint8List data);
  Uint8List serialize();
}
```

#### LongTermSecretKey

```dart
class LongTermSecretKey {
  LongTermSecretKey({required Uint8List decapsulationKey, required Uint8List signingKey});
}
```

#### EphemeralPreKey

```dart
class EphemeralPreKey {
  EphemeralPreKey({
    required Uint8List ephemeralPublicKey,
    required Uint8List ephemeralSecretKey,
    required Uint8List signature,
  });
}
```

#### PreKeyBundle

```dart
class PreKeyBundle {
  PreKeyBundle({
    required LongTermPublicKey longTermPublicKey,
    required Uint8List ephemeralPublicKey,
    required Uint8List signature,
  });
  factory PreKeyBundle.deserialize(Uint8List data);
  Uint8List serialize();
}
```

#### KeyExchangeMessage

```dart
class KeyExchangeMessage {
  KeyExchangeMessage({
    required Uint8List ciphertext,
    required Uint8List ephemeralCiphertext,
    required Uint8List encryptedSignature,
  });
  factory KeyExchangeMessage.deserialize(Uint8List data);
  Uint8List serialize();
}
```

#### SessionId

```dart
class SessionId {
  SessionId(Uint8List data);
  factory SessionId.build({
    required String identityA,
    required String identityB,
    required LongTermPublicKey lpkA,
    required LongTermPublicKey lpkB,
    required Uint8List ephemeralPublicKey,
    required Uint8List ciphertext,
    required Uint8List ephemeralCiphertext,
  });
  final Uint8List data;
}
```

#### Session

```dart
class Session {
  Session({
    required SessionId sessionId,
    required Uint8List sessionKey,
    required String localIdentity,
    required String remoteIdentity,
    DateTime? createdAt,
  });
}
```

---

### Storage Interfaces

#### SecureStorage (client-side)

```dart
abstract class SecureStorage {
  Future<void> saveIdentity(String userId, LongTermPublicKey publicKey, LongTermSecretKey secretKey);
  Future<LongTermPublicKey?> getPublicKey(String userId);
  Future<LongTermSecretKey?> getSecretKey(String userId);
  Future<void> savePreKey(String userId, EphemeralPreKey preKey);
  Future<EphemeralPreKey?> getPreKey(String userId);
  Future<void> removePreKey(String userId);
  Future<void> clear();
}
```

#### Storage (server-side)

```dart
abstract class Storage {
  Future<void> registerUser(UserRecord record);
  Future<UserRecord?> getUser(String userId);
  Future<void> storePreKey(PreKeyRecord record);
  Future<PreKeyRecord?> getPreKey(String userId);
  Future<void> removePreKey(String userId);
  Future<void> storeMessage(MessageRecord record);
  Future<List<MessageRecord>> getMessages(String userId);
  Future<void> clearMessages(String userId);
  Future<int> getUserCount();
  Future<int> getPreKeyCount();
  Future<int> getMessageCount();
}
```

Implementations: `InMemoryStorage`, `FileStorage(String storagePath)`.

### Platform Storage Adapters

#### Firebase Firestore (`lattice_server_firebase`)

```dart
abstract class FirestoreAdapter {
  Future<void> setDocument(String collection, String documentId, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId);
  Future<List<Map<String, dynamic>>> getCollection(String collection, {String? whereField, String? whereValue});
  Future<void> deleteDocument(String collection, String documentId);
  Future<void> addDocument(String collection, Map<String, dynamic> data);
  Future<int> countDocuments(String collection);
}

class FirestoreStorage { ... }  // Uses FirestoreAdapter
class FirebaseConfig { ... }    // Project configuration
class FirebaseDeployer { ... }  // Cloud Run deployment
```

#### Serverpod PostgreSQL (`lattice_server_serverpod`)

```dart
abstract class DatabaseAdapter {
  Future<void> insert(String table, Map<String, dynamic> values);
  Future<Map<String, dynamic>?> findOne(String table, String key, String value);
  Future<List<Map<String, dynamic>>> findAll(String table, {String? whereKey, String? whereValue});
  Future<void> delete(String table, String key, String value);
  Future<int> count(String table);
}

class ServerpodStorage { ... }           // Uses DatabaseAdapter
class ServerpodEndpointHandlers { ... }  // Endpoint handler templates
class Migration { ... }                 // SQL migration scripts
```

#### Supabase PostgreSQL (`lattice_server_supabase`)

```dart
abstract class SupabaseAdapter {
  Future<void> insert(String table, Map<String, dynamic> values);
  Future<List<Map<String, dynamic>>> select(String table, {Map<String, String>? filters});
  Future<void> update(String table, Map<String, dynamic> values, String matchKey, String matchValue);
  Future<void> delete(String table, String matchKey, String matchValue);
  Future<int> count(String table);
}

class SupabaseStorage { ... }    // Uses SupabaseAdapter
class SupabaseConfig { ... }     // Project configuration
class SupabaseMigration { ... }  // SQL migration scripts with optional RLS
```
