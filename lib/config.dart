/// Environment-aware app configuration.
///
/// Which environment is used is chosen at BUILD time via a single define:
///
///   flutter run                              # defaults to Environment.local
///   flutter run --dart-define=ENV=staging
///   flutter build ... --dart-define=ENV=prod
///
/// Everything here is `const`, so the selected environment's values are compiled
/// in and the others are tree-shaken away. This is a Flutter-native, type-safe
/// alternative to a runtime `.env` file — no bundled asset, no file I/O.
///
/// SECURITY: compile-time defines are still extractable from a shipped app
/// bundle. Only publishable/anon-level values belong here (Supabase URL,
/// publishable key, backend URL). Real secrets (service-role key, OpenAI key)
/// live ONLY on the server and must never appear in this file.
///
/// Host note:
///   - iOS simulator / macOS / web:  127.0.0.1 works.
///   - Android emulator:             use 10.0.2.2 to reach the host machine.
library;

enum Environment { local, staging, prod }

/// The per-environment values. Keep the shape identical across environments.
class _EnvValues {
  const _EnvValues({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.backendUrl,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String backendUrl;
}

class AppConfig {
  // The raw ENV define, resolved to an [Environment]. Defaults to local so a
  // plain `flutter run` just works against the local stack.
  static const String _envName = String.fromEnvironment('ENV', defaultValue: 'local');

  static Environment get environment => switch (_envName) {
        'staging' => Environment.staging,
        'prod' => Environment.prod,
        _ => Environment.local,
      };

  // One entry per environment. `local` holds the working local-dev values;
  // staging/prod are placeholders — fill in when those backends exist.
  static const Map<Environment, _EnvValues> _byEnv = {
    Environment.local: _EnvValues(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
      backendUrl: 'http://127.0.0.1:3000',
    ),
    Environment.staging: _EnvValues(
      supabaseUrl: 'https://TODO-staging.supabase.co',
      supabasePublishableKey: 'TODO-staging-publishable-key',
      backendUrl: 'https://TODO-staging.herokuapp.com',
    ),
    Environment.prod: _EnvValues(
      supabaseUrl: 'https://TODO-prod.supabase.co',
      supabasePublishableKey: 'TODO-prod-publishable-key',
      backendUrl: 'https://TODO-prod.herokuapp.com',
    ),
  };

  static _EnvValues get _current => _byEnv[environment]!;

  // Public accessors used across the app.
  static String get supabaseUrl => _current.supabaseUrl;
  static String get supabasePublishableKey => _current.supabasePublishableKey;
  static String get backendUrl => _current.backendUrl;

  /// Storage bucket that audio is uploaded to (matches the backend + RLS).
  /// Environment-independent, so it stays a plain constant.
  static const storageBucket = 'recordings';

  /// Recording limits (MVP) — mirrors the backend/API contract.
  static const maxRecordingSeconds = 90;
}
