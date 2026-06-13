class AppConstants {
  // Use --dart-define=API_BASE_URL=... and --dart-define=WS_URL=...
  // Fallbacks are provided for ease of development.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL', 
    defaultValue: 'http://localhost:8082/api',
  );
  
  static const String wsUrl = String.fromEnvironment(
    'WS_URL', 
    defaultValue: 'ws://localhost:8082/ws',
  );
}
