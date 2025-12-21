import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
import '../services/livekit_service.dart';
import '../services/websocket_service.dart';
import '../services/foreground_service.dart';
import '../services/settings_service.dart';

/// Audio Provider - manages voice chat state
class AudioProvider extends ChangeNotifier {
  final ApiService _apiService;
  final LivekitService _livekitService;
  final WebSocketService _wsService;
  
  bool _isInVoiceChannel = false;
  bool _isMuted = true;  // Start muted by default
  bool _isDeafened = false;
  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _pendingVoiceRejoin = false;  // Track if we need to rejoin voice after reconnect
  String? _error;
  int _audioBitrateKbps = 32; // Current bitrate setting
  
  String? _currentRoomId;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentRoomName;
  
  // Store last room info for auto-rejoin after network recovery
  String? _lastRoomId;
  String? _lastUserId;
  String? _lastUserName;
  String? _lastRoomName;
  
  // Session expiration stream - listen to this to navigate to login
  final _sessionExpiredController = StreamController<void>.broadcast();
  Stream<void> get onSessionExpired => _sessionExpiredController.stream;
  
  StreamSubscription? _speakingChangedSub;
  StreamSubscription? _participantJoinedSub;
  StreamSubscription? _participantLeftSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _connectionStateSub;
  StreamSubscription? _reconnectingSub;
  StreamSubscription? _wsConnectionSub;  // WebSocket connection listener

  AudioProvider({
    ApiService? apiService,
    LivekitService? livekitService,
    required WebSocketService wsService,
  })  : _apiService = apiService ?? ApiService(),
        _livekitService = livekitService ?? LivekitService(),
        _wsService = wsService {
    _setupListeners();
    _loadSettings();
  }

  // Getters
  bool get isInVoiceChannel => _isInVoiceChannel;
  bool get isMuted => _isMuted;
  bool get isDeafened => _isDeafened;
  bool get isConnecting => _isConnecting;
  bool get isReconnecting => _isReconnecting;
  String? get error => _error;
  LivekitService get livekitService => _livekitService;
  int get audioBitrateKbps => _audioBitrateKbps;

  /// Load settings from storage
  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    _audioBitrateKbps = settings.audioBitrateKbps;
    notifyListeners();
  }

  /// Set audio bitrate (8-128 kbps)
  Future<void> setAudioBitrate(int kbps) async {
    _audioBitrateKbps = kbps.clamp(8, 128);
    final settings = await SettingsService.getInstance();
    await settings.setAudioBitrateKbps(_audioBitrateKbps);
    notifyListeners();
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Join voice channel
  Future<bool> joinVoice(String roomId, String userId, String userName, {String? roomName}) async {
    if (_isInVoiceChannel || _isConnecting) return false;
    
    _isConnecting = true;
    _error = null;
    notifyListeners();

    try {
      // Request microphone permission
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        _error = 'Microphone permission denied';
        _isConnecting = false;
        notifyListeners();
        return false;
      }

      // Start foreground service for background audio
      final displayName = roomName ?? roomId;
      await ForegroundServiceHandler.startService(displayName);

      // Get LiveKit token from server
      final tokenData = await _apiService.getLivekitToken(roomId, userId, userName);
      final token = tokenData['token'] as String;
      final url = tokenData['url'] as String;

      // Connect to LiveKit with configured bitrate
      await _livekitService.connect(url, token, audioBitrateBps: _audioBitrateKbps * 1000);
      
      _currentRoomId = roomId;
      _currentUserId = userId;
      _currentUserName = userName;
      _currentRoomName = displayName;
      _isInVoiceChannel = true;
      _isMuted = true;  // Start muted
      _isReconnecting = false;
      _isConnecting = false;
      _pendingVoiceRejoin = false;  // Clear pending rejoin flag
      
      // Store for potential auto-rejoin after network recovery
      _lastRoomId = roomId;
      _lastUserId = userId;
      _lastUserName = userName;
      _lastRoomName = displayName;
      
      // Keep screen on during call
      await WakelockPlus.enable();

      // Sync initial state (muted by default) to server so others see correct icons
      await _apiService.updateUserState(
        _currentUserId!,
        isMuted: _isMuted,
        isDeafened: _isDeafened,
        isSpeaking: false,
      );
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to join voice: $e';
      _isConnecting = false;
      // Stop foreground service on failure
      await ForegroundServiceHandler.stopService();
      notifyListeners();
      return false;
    }
  }

  /// Leave voice channel (intentional - user action)
  Future<void> leaveVoice() async {
    // Clear last room info - intentional leave should NOT auto-rejoin
    _lastRoomId = null;
    _lastUserId = null;
    _lastUserName = null;
    _lastRoomName = null;
    _pendingVoiceRejoin = false;
    
    await _livekitService.disconnect();
    
    // Stop foreground service
    await ForegroundServiceHandler.stopService();
    
    _isInVoiceChannel = false;
    _isMuted = true;
    _isDeafened = false;
    _isReconnecting = false;
    _currentRoomId = null;
    _currentUserId = null;
    _currentUserName = null;
    _currentRoomName = null;
    
    // Allow screen to turn off
    await WakelockPlus.disable();
    
    notifyListeners();
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    if (!_isInVoiceChannel) return;

    final newMuteState = !_isMuted;
    
    try {
      await _livekitService.setMicrophoneEnabled(!newMuteState);
      _isMuted = newMuteState;
      
      // Update server state
      if (_currentUserId != null) {
        await _apiService.updateUserState(_currentUserId!, isMuted: _isMuted);
        // If muted, also clear speaking state on server immediately
        if (_isMuted) {
          _wsService.sendSpeakingState(false);
          await _apiService.updateUserState(_currentUserId!, isSpeaking: false);
        }
      }
      
      notifyListeners();
    } catch (e) {
      _error = 'Failed to toggle mute: $e';
      notifyListeners();
    }
  }

  /// Toggle deafen
  Future<void> toggleDeafen() async {
    if (!_isInVoiceChannel) return;

    _isDeafened = !_isDeafened;
    
    try {
      // Actually mute/unmute incoming audio via LiveKit
      await _livekitService.setDeafened(_isDeafened);
      
      // When deafening, also mute outgoing audio
      if (_isDeafened && !_isMuted) {
        await toggleMute();
      }
      
      // Update server state
      if (_currentUserId != null) {
        await _apiService.updateUserState(_currentUserId!, isDeafened: _isDeafened);
      }
      
      notifyListeners();
    } catch (e) {
      // Revert state on error
      _isDeafened = !_isDeafened;
      _error = 'Failed to toggle deafen: $e';
      notifyListeners();
    }
  }

  /// Set speaking state (called from voice activity detection)
  void setSpeaking(bool isSpeaking) {
    _wsService.sendSpeakingState(isSpeaking);
  }

  void _setupListeners() {
    _speakingChangedSub = _livekitService.onSpeakingChanged.listen((data) {
      // Handle speaking changes from LiveKit
      final participantId = data['participantId'] as String?;
      final isSpeaking = data['isSpeaking'] as bool? ?? false;
      
      // If this is the local user speaking, send to WebSocket server
      // Note: LiveKit identity is set to userId, not userName
      if (participantId != null && participantId == _currentUserId) {
        _wsService.sendSpeakingState(isSpeaking);
      }
      notifyListeners();
    });

    _participantJoinedSub = _livekitService.onParticipantJoined.listen((participant) {
      notifyListeners();
    });

    _participantLeftSub = _livekitService.onParticipantLeft.listen((participant) {
      notifyListeners();
    });

    _errorSub = _livekitService.onError.listen((error) {
      _error = error;
      notifyListeners();
    });

    // Listen for connection state changes (network disconnections)
    _connectionStateSub = _livekitService.onConnectionStateChanged.listen((isConnected) {
      if (!isConnected && _isInVoiceChannel && !_isReconnecting) {
        // Network disconnection detected while in voice channel (and not already reconnecting)
        print('⚠ LiveKit disconnected - network issue detected');
        _isInVoiceChannel = false;
        _isReconnecting = false;
        _error = 'Disconnected from voice - network error';
        
        // Mark for auto-rejoin when network recovers (only if we have room info)
        if (_lastRoomId != null && _lastUserId != null) {
          _pendingVoiceRejoin = true;
          print('📋 Pending voice rejoin set for room: $_lastRoomId');
        }
        
        // Notify other users of disconnection
        _wsService.sendNetworkStatus('disconnected');
        
        // Stop foreground service
        ForegroundServiceHandler.stopService();
        WakelockPlus.disable();
        
        notifyListeners();
      } 
      
      if (isConnected) {
        // Connected (initial or reconnected)
        _isReconnecting = false;
        _error = null;
        _pendingVoiceRejoin = false;  // Clear pending - we're connected
        if (_currentRoomId != null) {
          _isInVoiceChannel = true;
          // Notify other users we're back online
          _wsService.sendNetworkStatus('good');
        }
        notifyListeners();
      }
    });

    // Listen for reconnecting state
    _reconnectingSub = _livekitService.onReconnecting.listen((isReconnecting) {
      _isReconnecting = isReconnecting;
      if (isReconnecting) {
        _error = 'Reconnecting...';
        // Notify other users we're having network issues (weak/reconnecting)
        _wsService.sendNetworkStatus('weak');
      } else {
        _error = null;
        _isReconnecting = false;
      }
      notifyListeners();
    });

    // Listen for WebSocket connection state to trigger auto-rejoin
    _wsConnectionSub = _wsService.onConnectionStateChanged.listen((isWsConnected) {
      if (isWsConnected && _pendingVoiceRejoin) {
        // WebSocket reconnected and we have a pending voice rejoin
        _attemptVoiceRejoin();
      }
    });
  }

  /// Attempt to automatically rejoin voice after network recovery
  Future<void> _attemptVoiceRejoin() async {
    if (!_pendingVoiceRejoin) return;
    if (_lastRoomId == null || _lastUserId == null || _lastUserName == null) {
      _pendingVoiceRejoin = false;
      return;
    }
    
    // Prevent multiple rejoin attempts
    if (_isConnecting || _isInVoiceChannel) {
      _pendingVoiceRejoin = false;
      return;
    }
    
    print('🔄 Attempting automatic voice rejoin to: $_lastRoomName ($_lastRoomId)');
    _error = 'Rejoining voice...';
    notifyListeners();
    
    // Small delay to ensure network is stable
    await Future.delayed(const Duration(seconds: 1));
    
    // Check again if we should still rejoin
    if (!_pendingVoiceRejoin || _isInVoiceChannel) {
      return;
    }
    
    try {
      // IMPORTANT: First join the room via API - this broadcasts 'user-joined' to others
      print('📡 Calling joinRoom API to notify other users...');
      await _apiService.joinRoom(_lastUserId!, _lastRoomId!);
      
      // Now connect to LiveKit for voice
      final success = await joinVoice(
        _lastRoomId!,
        _lastUserId!,
        _lastUserName!,
        roomName: _lastRoomName,
      );
      
      if (success) {
        print('✓ Automatic voice rejoin successful!');
        _error = null;
      } else {
        print('✗ Automatic voice rejoin failed');
        _pendingVoiceRejoin = false;  // Don't retry forever
      }
    } on ApiException catch (e) {
      print('✗ Automatic voice rejoin API error: $e');
      _pendingVoiceRejoin = false;
      
      if (e.isSessionExpired) {
        // Session was cleaned up due to long disconnection
        // Clear stored room info - user needs to rejoin manually
        _lastRoomId = null;
        _lastUserId = null;
        _lastUserName = null;
        _lastRoomName = null;
        _error = 'Session expired. Please login again.';
        print('⚠️ Session expired - navigating to login');
        
        // Notify listeners that session expired - triggers navigation to login
        _sessionExpiredController.add(null);
      } else {
        _error = 'Failed to rejoin: ${e.message}';
      }
    } catch (e) {
      print('✗ Automatic voice rejoin error: $e');
      _pendingVoiceRejoin = false;  // Don't retry forever
      _error = 'Failed to rejoin voice';
    }
    
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _speakingChangedSub?.cancel();
    _participantJoinedSub?.cancel();
    _participantLeftSub?.cancel();
    _errorSub?.cancel();
    _connectionStateSub?.cancel();
    _reconnectingSub?.cancel();
    _wsConnectionSub?.cancel();
    _sessionExpiredController.close();
    _livekitService.dispose();
    _apiService.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}

