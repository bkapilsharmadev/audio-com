import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
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
  String? _stableUserId; // Persistent device identity

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

  /// Initialize - load stable userId, but don't auto-login
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get or create stable userId (persists forever)
      _stableUserId = prefs.getString('stableUserId');
      if (_stableUserId == null) {
        _stableUserId = const Uuid().v4();
        await prefs.setString('stableUserId', _stableUserId!);
        print('Generated new stableUserId: $_stableUserId');
      } else {
        print('Loaded existing stableUserId: $_stableUserId');
      }
      
      // Clear session data - user must enter credentials
      // but keep stableUserId for reconnection identity
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

  /// Register a new user (or reconnect with existing identity)
  Future<bool> register(String name, String serverPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Pass stableUserId to server for session ownership
      final user = await _apiService.register(name, serverPassword, userId: _stableUserId);
      _currentUser = user;
      
      // Save session info (not the userId - that's already stable)
      final prefs = await SharedPreferences.getInstance();
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
    
    // Clear session data but keep stableUserId
    final prefs = await SharedPreferences.getInstance();
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
