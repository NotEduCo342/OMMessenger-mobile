class AppConstants {
  // Use --dart-define=API_BASE_URL=... and --dart-define=WS_URL=...
  // Fallbacks are provided for ease of development.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL', 
    defaultValue: 'https://api-om.wexun.tech/api',
  );
  
  static const String wsUrl = String.fromEnvironment(
    'WS_URL', 
    defaultValue: 'wss://api-om.wexun.tech/ws',
  );
}
