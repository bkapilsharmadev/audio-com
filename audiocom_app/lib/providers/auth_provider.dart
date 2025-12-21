import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

/// Authentication Provider - manages user state and auth flow
/// 
/// Identity Model:
/// - (userId + username) is an immutable pair
/// - If username changes → new userId is generated
/// - A userId may reconnect, but may NOT rename
class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final WebSocketService _wsService;
  
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  
  // Stored identity (userId + username pair)
  String? _storedUserId;
  String? _storedUsername;

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
  String? get storedUsername => _storedUsername;

  /// Initialize - load stored identity pair
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load stored identity pair
      _storedUserId = prefs.getString('identityUserId');
      _storedUsername = prefs.getString('identityUsername');
      
      if (_storedUserId != null && _storedUsername != null) {
        print('Loaded identity: $_storedUsername ($_storedUserId)');
      } else {
        print('No stored identity found');
      }
      
      _currentUser = null;
    } catch (e) {
      print('Error initializing auth: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Register/login with username
  /// If username differs from stored → new identity created
  Future<bool> register(String name, String serverPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final trimmedName = name.trim();
      String userIdToUse;
      
      // Check if this is a reconnect or new identity
      if (_storedUserId != null && _storedUsername != null) {
        if (trimmedName.toLowerCase() == _storedUsername!.toLowerCase()) {
          // Same username → reconnect with existing userId
          userIdToUse = _storedUserId!;
          print('Reconnecting as: $trimmedName ($userIdToUse)');
        } else {
          // Different username → NEW IDENTITY
          print('Username changed: $_storedUsername → $trimmedName');
          
          // Invalidate old session (best-effort)
          await _invalidateOldSession(_storedUserId!);
          
          // Generate new userId
          userIdToUse = const Uuid().v4();
          print('New identity created: $trimmedName ($userIdToUse)');
        }
      } else {
        // No stored identity → generate new
        userIdToUse = const Uuid().v4();
        print('First time login: $trimmedName ($userIdToUse)');
      }
      
      // Register with server
      final user = await _apiService.register(trimmedName, serverPassword, userId: userIdToUse);
      _currentUser = user;
      
      // Persist the identity pair (immutable)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('identityUserId', user.id);
      await prefs.setString('identityUsername', user.name);
      _storedUserId = user.id;
      _storedUsername = user.name;
      
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
  
  /// Invalidate old session on server (best-effort, fire-and-forget)
  Future<void> _invalidateOldSession(String oldUserId) async {
    try {
      // Try to connect and send invalidate message
      await _wsService.connect(oldUserId);
      _wsService.sendMessage({
        'type': 'invalidate-user',
        'userId': oldUserId,
      });
      await _wsService.disconnect();
      print('Sent invalidate for old session: $oldUserId');
    } catch (e) {
      // Best-effort - server will clean up via heartbeat anyway
      print('Could not invalidate old session (will timeout): $e');
    }
  }

  /// Logout - clears identity completely
  Future<void> logout() async {
    if (_currentUser != null) {
      try {
        await _apiService.leaveUser(_currentUser!.id);
      } catch (e) {
        print('Error leaving server: $e');
      }
    }

    await _wsService.disconnect();
    
    // Clear identity completely on explicit logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('identityUserId');
    await prefs.remove('identityUsername');
    _storedUserId = null;
    _storedUsername = null;
    
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  /// Handle session expiration - clears current user but keeps stored username
  /// This allows the user to easily re-login with the same name
  void handleSessionExpired() {
    print('⚠️ Session expired - clearing current user');
    _wsService.disconnect();
    _currentUser = null;
    _error = 'Session expired. Please login again.';
    // Keep _storedUsername so user can easily re-login with same name
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
