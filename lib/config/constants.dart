class AppConstants {
  // Use --dart-define=API_BASE_URL=... and --dart-define=WS_URL=...
  // Fallbacks are provided for ease of development.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL', 
    defaultValue: 'https://om.noteduco342.ir/api',
  );
  
  static const String wsUrl = String.fromEnvironment(
    'WS_URL', 
    defaultValue: 'wss://om.noteduco342.ir/ws',
  );
}
