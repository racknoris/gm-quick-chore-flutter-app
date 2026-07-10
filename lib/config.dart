/// Environment-aware app configuration.
///
/// The environment is chosen at BUILD time via a single define. Each local
/// variant exists because "localhost" is a DIFFERENT address depending on where
/// the app runs:
///
///   flutter run                                        # localSimulatorIOS (default)
///   flutter run --dart-define=ENV=localSimulatorIOS    # iOS simulator / macOS / web -> 127.0.0.1
///   flutter run --dart-define=ENV=localEmulatorAndroid # Android emulator          -> 10.0.2.2
///   flutter run --dart-define=ENV=localDevice          # physical device over Wi-Fi -> LAN IP
///   flutter run --dart-define=ENV=staging
///   flutter build ... --dart-define=ENV=prod
///
/// Everything here is `const`, so the selected environment's values are compiled
/// in and the others are tree-shaken away. Flutter-native, type-safe, no runtime
/// `.env` file, no bundled asset.
///
/// SECURITY: compile-time defines are still extractable from a shipped app
/// bundle. Only publishable/anon-level values belong here (Supabase URL,
/// publishable key, backend URL). Real secrets (service-role key, OpenAI key)
/// live ONLY on the server and must never appear in this file.
library;

enum Environment {
  /// iOS simulator, macOS, or web — reaches the host at 127.0.0.1.
  localSimulatorIOS,

  /// Android emulator — reaches the host machine via the 10.0.2.2 alias.
  localEmulatorAndroid,

  /// Physical phone/tablet on the same Wi-Fi — reaches the host by its LAN IP.
  /// The LAN IP is DHCP-assigned; re-check with `ipconfig getifaddr en0` if it
  /// changes. Requires cleartext HTTP (already allowed in the debug/profile
  /// Android manifests; a real iPhone additionally needs an ATS exception).
  localDevice,

  staging,
  prod,
}

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
  // The raw ENV define, resolved to an [Environment]. Defaults to the iOS
  // simulator / macOS / web target so a plain `flutter run` just works.
  static const String _envName =
      String.fromEnvironment('ENV', defaultValue: 'localSimulatorIOS');

  static Environment get environment => switch (_envName) {
        'localEmulatorAndroid' => Environment.localEmulatorAndroid,
        'localDevice' => Environment.localDevice,
        'staging' => Environment.staging,
        'prod' => Environment.prod,
        _ => Environment.localSimulatorIOS,
      };

  // ---------------------------------------------------------------------------
  // Per-environment values. The three `local*` entries point at the SAME local
  // stack — only the host differs. Publishable key is identical for all locals.
  // Update `localDevice`'s host to your Mac's current LAN IP when testing on a
  // real device. staging/prod are placeholders — fill in when they exist.
  // ---------------------------------------------------------------------------
  static const _localPublishableKey =
      'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

  static const Map<Environment, _EnvValues> _byEnv = {
    Environment.localSimulatorIOS: _EnvValues(
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: _localPublishableKey,
      backendUrl: 'http://127.0.0.1:3000',
    ),
    Environment.localEmulatorAndroid: _EnvValues(
      supabaseUrl: 'http://10.0.2.2:54321',
      supabasePublishableKey: _localPublishableKey,
      backendUrl: 'http://10.0.2.2:3000',
    ),
    Environment.localDevice: _EnvValues(
      supabaseUrl: 'http://10.0.0.6:54321', // <- your Mac's LAN IP
      supabasePublishableKey: _localPublishableKey,
      backendUrl: 'http://10.0.0.6:3000',
    ),
    Environment.staging: _EnvValues(
      supabaseUrl: 'https://irvzngrxibyflhygjjex.supabase.co',
      supabasePublishableKey: 'sb_publishable_YXKGKvtve1BaZX6Zu3sJDw_-vBTlxnf',
      backendUrl: 'https://gm-quick-chore-d393b31d5d51.herokuapp.com',
    ),
    Environment.prod: _EnvValues(
      supabaseUrl: 'https://irvzngrxibyflhygjjex.supabase.co',
      supabasePublishableKey: 'sb_publishable_YXKGKvtve1BaZX6Zu3sJDw_-vBTlxnf',
      backendUrl: 'https://gm-quick-chore-d393b31d5d51.herokuapp.com',
    ),
  };

  static _EnvValues get _current => _byEnv[environment]!;

  // Public accessors used across the app.
  static String get supabaseUrl => _current.supabaseUrl;
  static String get supabasePublishableKey => _current.supabasePublishableKey;
  static String get backendUrl => _current.backendUrl;

  /// Recording limits — mirrors the backend/API contract. Up to 30 min of
  /// speech; at 64 kbps mono that's ≈ 14 MB, safely under OpenAI's 25 MB limit.
  static const maxRecordingSeconds = 30 * 60; // 30 minutes
}
