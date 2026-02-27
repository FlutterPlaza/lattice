/// PostgreSQL migration for Lattice tables.
///
/// Run this migration in your Serverpod project or directly against PostgreSQL.
///
/// Example usage:
/// ```dart
/// await session.db.unsafeExecute(Migration.createTables);
/// ```
class Migration {
  /// SQL to create the Lattice tables and indexes.
  static const String createTables = '''
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
CREATE INDEX IF NOT EXISTS idx_lattice_prekeys_user ON lattice_prekeys(user_id);
''';

  /// SQL to drop all Lattice tables.
  static const String dropTables = '''
DROP TABLE IF EXISTS lattice_messages;
DROP TABLE IF EXISTS lattice_prekeys;
DROP TABLE IF EXISTS lattice_users;
''';
}
