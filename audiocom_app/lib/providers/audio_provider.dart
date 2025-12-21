import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
import '../services/livekit_service.dart';
import '../services/websocket_service.dart';
import '../services/foreground_service.dart';

/// Audio Provider - manages voice chat state
class AudioProvider extends ChangeNotifier {
  final ApiService _apiService;
  final LivekitService _livekitService;
  final WebSocketService _wsService;
  
  bool _isInVoiceChannel = false;
  bool _isMuted = true;  // Start muted by default
  bool _isDeafened = false;
  bool _isConnecting = false;
  String? _error;
  
  String? _currentRoomId;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentRoomName;
  
  StreamSubscription? _speakingChangedSub;
  StreamSubscription? _participantJoinedSub;
  StreamSubscription? _participantLeftSub;
  StreamSubscription? _errorSub;

  AudioProvider({
    ApiService? apiService,
    LivekitService? livekitService,
    required WebSocketService wsService,
  })  : _apiService = apiService ?? ApiService(),
        _livekitService = livekitService ?? LivekitService(),
        _wsService = wsService {
    _setupListeners();
  }

  // Getters
  bool get isInVoiceChannel => _isInVoiceChannel;
  bool get isMuted => _isMuted;
  bool get isDeafened => _isDeafened;
  bool get isConnecting => _isConnecting;
  String? get error => _error;
  LivekitService get livekitService => _livekitService;

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

      // Connect to LiveKit
      await _livekitService.connect(url, token);
      
      _currentRoomId = roomId;
      _currentUserId = userId;
      _currentUserName = userName;
      _currentRoomName = displayName;
      _isInVoiceChannel = true;
      _isMuted = true;  // Start muted
      _isConnecting = false;
      
      // Keep screen on during call
      await WakelockPlus.enable();
      
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

  /// Leave voice channel
  Future<void> leaveVoice() async {
    await _livekitService.disconnect();
    
    // Stop foreground service
    await ForegroundServiceHandler.stopService();
    
    _isInVoiceChannel = false;
    _isMuted = true;
    _isDeafened = false;
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
    _livekitService.dispose();
    _apiService.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}
