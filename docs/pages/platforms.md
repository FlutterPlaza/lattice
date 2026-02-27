# Platform Integrations

Lattice supports multiple deployment platforms and storage backends. The core protocol logic (`lattice_crypto` and `lattice_protocol`) is platform-agnostic. The server layer adapts to different hosting environments.

## Architecture

```
                    lattice_crypto (primitives)
                           |
                    lattice_protocol (SC-AKE/SC-DAKE)
                           |
          +----------------+----------------+
          |                |                |
   lattice_server    lattice_server    lattice_server
     (Shelf)          _serverpod        _firebase
          |                |                |
    InMemoryStorage   PostgreSQL      Firestore
    FileStorage       (Serverpod)     Cloud Run
```

## Platform Comparison

| Platform | Runtime | Storage | Auth | Best For |
|----------|---------|---------|------|----------|
| **Shelf (default)** | Dart AOT binary | In-memory / File | Bearer tokens | Development, simple deployments |
| **Firebase** | Cloud Run | Firestore | Firebase Auth | Firebase ecosystem, serverless |
| **Serverpod** | Serverpod runtime | PostgreSQL | Serverpod auth | Production Dart backends |
| **Supabase** | External server | Supabase PostgreSQL | Supabase Auth | Supabase ecosystem |
| **Docker** | Container | Mounted volume | Custom | Any cloud or on-premise |

---

## Firebase Cloud Run

Deploy the Lattice server to Firebase using Cloud Run for compute and Firestore for storage.

### Setup

1. Install Firebase CLI and Google Cloud SDK:

```bash
npm install -g firebase-tools
# Install gcloud: https://cloud.google.com/sdk/docs/install
```

2. Initialize Firebase project:

```bash
firebase login
firebase init
```

3. Configure deployment:

```dart
import 'package:lattice_server_firebase/lattice_server_firebase.dart';

final config = FirebaseConfig(
  projectId: 'your-project-id',
  region: 'us-central1',
  serviceName: 'lattice-server',
  minInstances: 1,
  maxInstances: 10,
);
```

### Deploy

```bash
# Using the deploy CLI
dart run tools/deploy/bin/deploy.dart deploy --target firebase

# Or manually
docker build -t lattice-server -f packages/lattice_server/Dockerfile .
gcloud builds submit --tag gcr.io/your-project/lattice-server
gcloud run deploy lattice-server \
  --image gcr.io/your-project/lattice-server \
  --platform managed --region us-central1
firebase deploy --only hosting
```

### Firestore Storage

Use Firestore as the storage backend instead of in-memory or file storage:

```dart
import 'package:lattice_server_firebase/lattice_server_firebase.dart';

// Implement the FirestoreAdapter using the Firebase Admin SDK
class MyFirestoreAdapter implements FirestoreAdapter {
  final Firestore firestore;
  MyFirestoreAdapter(this.firestore);

  @override
  Future<void> setDocument(String collection, String docId, Map<String, dynamic> data) async {
    await firestore.collection(collection).doc(docId).set(data);
  }
  // ... implement other methods
}

final storage = FirestoreStorage(MyFirestoreAdapter(firestore));
await storage.registerUser('alice', publicKeyData);
```

### Collections

Firestore uses these collections:
- `lattice_users` - User registrations (document ID = user ID)
- `lattice_prekeys` - Pre-key bundles (document ID = user ID)
- `lattice_messages` - Pending key exchange messages (auto-generated IDs)

---

## Serverpod

Integrate Lattice into an existing Serverpod project with PostgreSQL storage.

### Setup

1. Add the dependency to your Serverpod project:

```yaml
dependencies:
  lattice_server_serverpod:
    path: ../lattice/packages/lattice_server_serverpod
  lattice_crypto:
    path: ../lattice/packages/lattice_crypto
  lattice_protocol:
    path: ../lattice/packages/lattice_protocol
```

2. Run the database migration:

```dart
import 'package:lattice_server_serverpod/lattice_server_serverpod.dart';

// Execute in your migration or setup script
print(Migration.createTables);
```

Or run the SQL directly:

```sql
CREATE TABLE IF NOT EXISTS lattice_users (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR(255) UNIQUE NOT NULL,
  public_key TEXT NOT NULL,
  registered_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lattice_prekeys (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR(255) UNIQUE NOT NULL,
  bundle_data TEXT NOT NULL,
  uploaded_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lattice_messages (
  id SERIAL PRIMARY KEY,
  recipient_id VARCHAR(255) NOT NULL,
  sender_id VARCHAR(255) NOT NULL,
  message_data TEXT NOT NULL,
  sent_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lattice_messages_recipient ON lattice_messages(recipient_id);
```

### Create Endpoints

```dart
import 'package:serverpod/serverpod.dart';
import 'package:lattice_server_serverpod/lattice_server_serverpod.dart';

class LatticeEndpoint extends Endpoint {
  ServerpodStorage _storage(Session session) {
    return ServerpodStorage(ServerpodDatabaseAdapter(session));
  }

  Future<Map<String, dynamic>> register(
    Session session,
    String userId,
    String publicKeyBase64,
  ) async {
    final handlers = ServerpodEndpointHandlers();
    return handlers.register(_storage(session), userId, publicKeyBase64);
  }

  Future<Map<String, dynamic>> uploadPreKey(
    Session session,
    String userId,
    String bundleBase64,
  ) async {
    final handlers = ServerpodEndpointHandlers();
    return handlers.uploadPreKey(_storage(session), userId, bundleBase64);
  }

  // ... add other endpoints similarly
}
```

### Implement the Database Adapter

```dart
class ServerpodDatabaseAdapter implements DatabaseAdapter {
  final Session session;
  ServerpodDatabaseAdapter(this.session);

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    final columns = values.keys.join(', ');
    final placeholders = List.generate(values.length, (i) => '\$${i + 1}').join(', ');
    await session.db.unsafeQuery(
      'INSERT INTO $table ($columns) VALUES ($placeholders)',
      values: values.values.toList(),
    );
  }

  @override
  Future<Map<String, dynamic>?> findOne(String table, String key, String value) async {
    final result = await session.db.unsafeQuery(
      'SELECT * FROM $table WHERE $key = \$1 LIMIT 1',
      values: [value],
    );
    if (result.isEmpty) return null;
    return result.first.toColumnMap();
  }

  // ... implement other methods
}
```

---

## Supabase

Use Supabase as a PostgreSQL storage backend for the Lattice server.

### Setup

1. Create a Supabase project at [supabase.com](https://supabase.com)

2. Run the migration in the Supabase SQL editor:

```sql
CREATE TABLE IF NOT EXISTS lattice_users (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT UNIQUE NOT NULL,
  public_key TEXT NOT NULL,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lattice_prekeys (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT UNIQUE NOT NULL,
  bundle_data TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lattice_messages (
  id BIGSERIAL PRIMARY KEY,
  recipient_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  message_data TEXT NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lattice_messages_recipient ON lattice_messages(recipient_id);
```

3. Optionally enable Row Level Security:

```sql
ALTER TABLE lattice_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE lattice_prekeys ENABLE ROW LEVEL SECURITY;
ALTER TABLE lattice_messages ENABLE ROW LEVEL SECURITY;
```

### Integration

```dart
import 'package:supabase/supabase.dart';
import 'package:lattice_server_supabase/lattice_server_supabase.dart';

class MySupabaseAdapter implements SupabaseAdapter {
  final SupabaseClient client;
  MySupabaseAdapter(this.client);

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    await client.from(table).insert(values);
  }

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    Map<String, String>? filters,
  }) async {
    var query = client.from(table).select();
    if (filters != null) {
      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }
    return await query;
  }

  @override
  Future<void> delete(String table, String matchKey, String matchValue) async {
    await client.from(table).delete().eq(matchKey, matchValue);
  }

  @override
  Future<int> count(String table) async {
    final result = await client.from(table).select().count();
    return result.count;
  }

  // ... implement update method
}

// Use with the Lattice server
final supabase = SupabaseClient('https://your-project.supabase.co', 'your-anon-key');
final storage = SupabaseStorage(MySupabaseAdapter(supabase));

await storage.registerUser('alice', publicKeyBytes);
final pk = await storage.getUserPublicKey('alice');
```

### Configuration

Use environment variables for Supabase credentials:

```dart
final config = SupabaseConfig(
  projectUrl: 'https://your-project.supabase.co',
  anonKey: 'your-anon-key',
  serviceRoleKey: 'your-service-role-key', // for server-side operations
);
```

---

## Choosing a Platform

### Development / Prototyping
Use the default **Shelf server** with **InMemoryStorage**. No external dependencies needed.

### Firebase Ecosystem
If you already use Firebase, deploy to **Cloud Run** with **Firestore** storage. Firebase Hosting proxies API requests to Cloud Run.

### Production Dart Backend
Use **Serverpod** with **PostgreSQL**. Serverpod provides built-in auth, caching, and connection pooling.

### Existing Supabase Project
Add **Supabase** as a storage backend. Deploy the Dart server anywhere and point it at your Supabase PostgreSQL instance.

### Multi-Instance Production
Any PostgreSQL-backed option (Serverpod, Supabase) supports horizontal scaling. InMemoryStorage and FileStorage are single-instance only.
