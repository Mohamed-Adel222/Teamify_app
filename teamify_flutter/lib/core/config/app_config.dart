/// Single source of truth for Teamify client configuration.
///
/// Compile-time overrides:
///   --dart-define=API_BASE_URL=https://...
///   --dart-define=LIVEKIT_URL=wss://your-project.livekit.cloud
///
/// Never put LIVEKIT_API_SECRET (or any provider secret) in Flutter.
class AppConfig {
  static const bool isDemoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://teamify-backend-5hq0.onrender.com',
  );

  /// Socket.IO connects to the same origin as the REST API.
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: apiBaseUrl,
  );

  /// Public LiveKit Cloud URL only (wss://… or https://…). Tokens are minted
  /// by Flask; this value is a display/fallback hint, not a secret.
  static const String livekitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: '',
  );

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration messageAckTimeout = Duration(seconds: 8);
}
