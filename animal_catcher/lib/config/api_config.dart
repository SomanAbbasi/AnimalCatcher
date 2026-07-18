/// Backend API configuration for the FAUNA BATTLER AI client.
///
/// [baseUrl] points at the FastAPI backend.
///
/// USB-connected phone (recommended for dev):
///   Run this ONCE on the PC so the phone's localhost forwards to the PC:
///       adb reverse tcp:8000 tcp:8000
///   Then `http://localhost:8000` on the phone reaches the PC's server.
///
/// Wi-Fi / same-LAN testing instead of USB:
///   Change [baseUrl] to your PC's LAN IPv4 address, e.g.
///       http://192.168.1.42:8000
///   and start the backend with `uvicorn main:app --host 0.0.0.0 --port 8000`.
///
/// The value can also be overridden at build time without editing this file:
///   flutter run --dart-define=BACKEND_BASE_URL=http://192.168.1.42:8000
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Timeout applied to the scan request (vision + taxonomy enrichment).
  static const Duration scanTimeout = Duration(seconds: 45);
}
