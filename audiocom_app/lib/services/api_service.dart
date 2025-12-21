import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/room.dart';

/// API Service for communicating with server
class ApiService {
  final String baseUrl;
  final http.Client _client;

  ApiService({String? baseUrl})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  /// Check server health
  Future<Map<String, dynamic>> healthCheck() async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.health}'),
    );
    return _handleResponse(response);
  }

  /// Get server info
  Future<Map<String, dynamic>> getServerInfo() async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.serverInfo}'),
    );
    return _handleResponse(response);
  }

  /// Register a new user (or reconnect with existing userId)
  Future<User> register(String name, String serverPassword, {String? userId}) async {
    final body = <String, dynamic>{
      'name': name,
      'serverPassword': serverPassword,
    };
    
    // Include userId for session identity/reconnection
    if (userId != null) {
      body['userId'] = userId;
    }
    
    final response = await _client.post(
      Uri.parse('$baseUrl${ApiConfig.register}'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _handleResponse(response);
    return User.fromJson(data);
  }

  /// Get all rooms
  Future<List<Room>> getRooms() async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.rooms}'),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => Room.fromJson(json)).toList();
  }

  /// Get room by ID
  Future<Room> getRoom(String roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.roomById(roomId)}'),
    );
    return Room.fromJson(_handleResponse(response));
  }

  /// Check if room requires password
  Future<Map<String, dynamic>> checkRoomPassword(String roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.roomRequiresPassword(roomId)}'),
    );
    return _handleResponse(response);
  }

  /// Get users in a room
  Future<List<User>> getUsersInRoom(String roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl${ApiConfig.users}?roomId=$roomId'),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => User.fromJson(json)).toList();
  }

  /// Join a room
  Future<Map<String, dynamic>> joinRoom(String userId, String roomId, {String? password}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl${ApiConfig.joinRoom(userId, roomId)}'),
      headers: _headers,
      body: jsonEncode({
        if (password != null) 'password': password,
      }),
    );
    return _handleResponse(response);
  }

  /// Leave (disconnect user)
  Future<void> leaveUser(String userId) async {
    await _client.post(
      Uri.parse('$baseUrl${ApiConfig.leaveUser(userId)}'),
      headers: _headers,
    );
  }

  /// Update user state (mute, deafen)
  Future<Map<String, dynamic>> updateUserState(
    String userId, {
    bool? isMuted,
    bool? isDeafened,
    bool? isSpeaking,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl${ApiConfig.userState(userId)}'),
      headers: _headers,
      body: jsonEncode({
        if (isMuted != null) 'isMuted': isMuted,
        if (isDeafened != null) 'isDeafened': isDeafened,
        if (isSpeaking != null) 'isSpeaking': isSpeaking,
      }),
    );
    return _handleResponse(response);
  }

  /// Get LiveKit token for voice chat
  Future<Map<String, dynamic>> getLivekitToken(
    String roomId,
    String userId,
    String userName,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl${ApiConfig.livekitToken}'),
      headers: _headers,
      body: jsonEncode({
        'roomId': roomId,
        'userId': userId,
        'userName': userName,
      }),
    );
    return _handleResponse(response);
  }

  /// Create a new room
  Future<Room> createRoom({
    required String name,
    String? description,
    bool isPrivate = false,
    int maxUsers = 25,
    String? password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl${ApiConfig.rooms}'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'description': description,
        'isPrivate': isPrivate,
        'maxUsers': maxUsers,
        if (password != null) 'password': password,
      }),
    );
    return Room.fromJson(_handleResponse(response));
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else {
      String error = 'Unknown error';
      String? code;
      
      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body);
          error = data['error'] ?? 'Unknown error';
          code = data['code'];
        } catch (_) {
          error = 'Request failed with status ${response.statusCode}';
        }
      } else {
        error = 'Request failed with status ${response.statusCode}';
      }
      
      throw ApiException(error, response.statusCode, code: code);
    }
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;

  ApiException(this.message, this.statusCode, {this.code});

  /// Check if this is a session expired error
  bool get isSessionExpired => code == 'SESSION_EXPIRED';

  @override
  String toString() => 'ApiException: $message (status: $statusCode, code: $code)';
}
