class AppConfig {
  static const bool isDemoMode = false;
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://teamify-backend-5hq0.onrender.com',
  );
}
