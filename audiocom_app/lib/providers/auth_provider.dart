import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

/// Authentication Provider - manages user state and auth flow
class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final WebSocketService _wsService;
  
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  AuthProvider({
    ApiService? apiService,
    WebSocketService? wsService,
  })  : _apiService = apiService ?? ApiService(),
        _wsService = wsService ?? WebSocketService();

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  WebSocketService get wsService => _wsService;

  /// Initialize - always start fresh (no auto-login)
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Clear any saved session data - always require fresh login
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userId');
      await prefs.remove('userName');
      await prefs.remove('userToken');
      
      _currentUser = null;
    } catch (e) {
      print('Error initializing auth: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Register a new user
  Future<bool> register(String name, String serverPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _apiService.register(name, serverPassword);
      _currentUser = user;
      
      // Save session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', user.id);
      await prefs.setString('userName', user.name);
      if (user.token != null) {
        await prefs.setString('userToken', user.token!);
      }
      
      // Connect WebSocket
      await _connectWebSocket();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Connection failed. Please check your server URL.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    if (_currentUser != null) {
      try {
        await _apiService.leaveUser(_currentUser!.id);
      } catch (e) {
        print('Error leaving server: $e');
      }
    }

    await _wsService.disconnect();
    
    // Clear saved session
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userToken');
    
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  /// Update user state (mute, deafen)
  Future<void> updateState({bool? isMuted, bool? isDeafened}) async {
    if (_currentUser == null) return;

    try {
      await _apiService.updateUserState(
        _currentUser!.id,
        isMuted: isMuted,
        isDeafened: isDeafened,
      );

      if (isMuted != null) _currentUser!.isMuted = isMuted;
      if (isDeafened != null) _currentUser!.isDeafened = isDeafened;
      
      notifyListeners();
    } catch (e) {
      print('Error updating user state: $e');
    }
  }

  /// Update room ID for current user
  void updateRoomId(String? roomId) {
    if (_currentUser != null) {
      _currentUser!.roomId = roomId;
      notifyListeners();
    }
  }

  Future<void> _connectWebSocket() async {
    if (_currentUser != null) {
      try {
        await _wsService.connect(_currentUser!.id);
      } catch (e) {
        print('WebSocket connection failed: $e');
      }
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsService.dispose();
    _apiService.dispose();
    super.dispose();
  }
}
