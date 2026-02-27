import 'dart:io';

/// Configuration for connecting to a Supabase project.
///
/// Holds the project URL and authentication keys required to interact with
/// the Supabase REST API. Can be constructed directly or loaded from
/// environment variables.
class SupabaseConfig {
  /// Creates a [SupabaseConfig] with the given connection parameters.
  const SupabaseConfig({
    required this.projectUrl,
    required this.anonKey,
    this.serviceRoleKey,
  });

  /// Creates a [SupabaseConfig] from environment variables.
  ///
  /// Reads the following variables:
  /// - `SUPABASE_URL` (required)
  /// - `SUPABASE_ANON_KEY` (required)
  /// - `SUPABASE_SERVICE_ROLE_KEY` (optional)
  ///
  /// Throws [StateError] if a required variable is missing or empty.
  factory SupabaseConfig.fromEnvironment() {
    return SupabaseConfig(
      projectUrl: _env('SUPABASE_URL'),
      anonKey: _env('SUPABASE_ANON_KEY'),
      serviceRoleKey: _envOrNull('SUPABASE_SERVICE_ROLE_KEY'),
    );
  }

  /// The Supabase project URL (e.g. `https://abc.supabase.co`).
  final String projectUrl;

  /// The public anonymous key for the Supabase project.
  final String anonKey;

  /// The service role key for elevated access. May be `null` if not needed.
  final String? serviceRoleKey;

  static String _env(String key) {
    final value = Platform.environment[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing environment variable: $key');
    }
    return value;
  }

  static String? _envOrNull(String key) {
    final value = Platform.environment[key];
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
