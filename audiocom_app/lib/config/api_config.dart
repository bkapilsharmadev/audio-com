/// API Configuration
class ApiConfig {
  // Change this to your server URL
  // For local development on Android emulator, use 10.0.2.2 instead of localhost
  // For iOS simulator, use localhost or your machine's IP
  // For physical devices, use your machine's local IP address
  static const String baseUrl = 'https://voice.bytesjourney.com';
  
  // WebSocket URL (same host, /ws path)
  static String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.host}:${uri.port}/ws';
  }
  
  // API Endpoints
  static const String health = '/api/health';
  static const String serverInfo = '/api/server/info';
  static const String rooms = '/api/rooms';
  static const String users = '/api/users';
  static const String register = '/api/users/register';
  static const String livekitToken = '/api/livekit/token';
  
  static String roomById(String roomId) => '/api/rooms/$roomId';
  static String userById(String userId) => '/api/users/$userId';
  static String joinRoom(String userId, String roomId) => '/api/users/$userId/join/$roomId';
  static String leaveUser(String userId) => '/api/users/$userId/leave';
  static String userState(String userId) => '/api/users/$userId/state';
  static String roomRequiresPassword(String roomId) => '/api/rooms/$roomId/requires-password';
}
