/// Compile-time / runtime configuration for the FAUNA BATTLER AI client.
///
/// Values can be overridden at build time without editing source using
/// `--dart-define`, e.g.:
///
///   flutter run \
///     --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8000 \
///     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// IMPORTANT: only the PUBLIC Supabase anon/publishable key belongs here.
/// The service-role key lives exclusively on the Python backend.
class AppConfig {
  AppConfig._();

  /// Base URL of the FastAPI backend.
  ///
  /// Defaults to the Android emulator loopback (`10.0.2.2`) which maps to the
  /// host machine's `localhost`. iOS simulator can use `http://localhost:8000`.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Public Supabase project URL.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Public Supabase anon/publishable key (safe for client bundling).
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Whether Supabase auth is wired up. When false, the app runs in a local
  /// "offline demo" mode so the UI/gameplay is fully explorable without a
  /// backing project.
  static bool get supabaseEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
