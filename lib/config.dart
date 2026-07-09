/// App configuration. Values can be overridden at build/run time with
/// --dart-define, e.g.
///   flutter run --dart-define=BACKEND_URL=https://your-app.herokuapp.com
///
/// Defaults target a local dev setup (local Supabase + local backend).
/// Note on hosts:
///   - iOS simulator / macOS / web:  127.0.0.1 works.
///   - Android emulator:             use 10.0.2.2 to reach the host machine.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  /// Storage bucket that audio is uploaded to (matches the backend + RLS).
  static const storageBucket = 'recordings';

  /// Recording limits (MVP) — mirrors the backend/API contract.
  static const maxRecordingSeconds = 90;
}
