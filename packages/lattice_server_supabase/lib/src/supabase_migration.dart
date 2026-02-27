/// SQL migration scripts for creating and dropping Lattice protocol tables
/// in a Supabase (PostgreSQL) database.
///
/// Run [createTables] in the Supabase SQL editor or via a migration tool to
/// set up the required schema. Optionally enable Row Level Security (RLS)
/// policies per your authentication setup.
class SupabaseMigration {
  SupabaseMigration._();

  /// SQL script that creates the Lattice protocol tables.
  static const String createTables = '''
-- Lattice Protocol Tables for Supabase

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

CREATE INDEX IF NOT EXISTS idx_lattice_messages_recipient
  ON lattice_messages(recipient_id);

-- Row Level Security (optional, enable per your auth setup)
-- ALTER TABLE lattice_users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE lattice_prekeys ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE lattice_messages ENABLE ROW LEVEL SECURITY;
''';

  /// SQL script that drops the Lattice protocol tables.
  static const String dropTables = '''
DROP TABLE IF EXISTS lattice_messages;
DROP TABLE IF EXISTS lattice_prekeys;
DROP TABLE IF EXISTS lattice_users;
''';
}
