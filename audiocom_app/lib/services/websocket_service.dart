import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/chat_message.dart';
import '../models/user.dart';

/// WebSocket message types from server
enum WsMessageType {
  userJoined,
  userLeft,
  userSpeaking,
  userStateChanged,
  userNetworkStatus,
  chatMessage,
  heartbeatAck,
  unknown,
}

/// Network status enum
enum NetworkStatus {
  good,
  weak,
  disconnected,
  reconnecting,
}

/// WebSocket Service for real-time communication
class WebSocketService {
  WebSocketChannel? _channel;
  String? _userId;
  String? _wsUrl;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _intentionalDisconnect = false;  // Track if disconnect was user-initiated
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const int _baseReconnectDelayMs = 2000;

  // Event streams
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _userJoinedController = StreamController<User>.broadcast();
  final _userLeftController = StreamController<String>.broadcast();
  final _userSpeakingController = StreamController<Map<String, dynamic>>.broadcast();
  final _userStateChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _userNetworkStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<User> get onUserJoined => _userJoinedController.stream;
  Stream<String> get onUserLeft => _userLeftController.stream;
  Stream<Map<String, dynamic>> get onUserSpeaking => _userSpeakingController.stream;
  Stream<Map<String, dynamic>> get onUserStateChanged => _userStateChangedController.stream;
  Stream<Map<String, dynamic>> get onUserNetworkStatus => _userNetworkStatusController.stream;
  Stream<ChatMessage> get onChatMessage => _chatMessageController.stream;
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;

  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<void> connect(String userId, {String? wsUrl}) async {
    // Cancel any pending reconnect
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    if (_isConnected) {
      await disconnect();
    }

    _userId = userId;
    _wsUrl = wsUrl ?? ApiConfig.wsUrl;
    _intentionalDisconnect = false;  // Reset for new connection

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl!));
      
      // Wait for connection
      await _channel!.ready;
      
      _isConnected = true;
      _reconnectAttempts = 0;  // Reset on successful connection
      _connectionStateController.add(true);

      // Register user
      _send({'type': 'register', 'userId': userId});

      // Start heartbeat
      _startHeartbeat();

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('WebSocket error: $error');
          _handleNetworkDisconnect();
        },
        onDone: () {
          print('WebSocket closed');
          _handleNetworkDisconnect();
        },
      );

      // Notify UI that current user is back to good
      _handleReconnect();
    } catch (e) {
      print('WebSocket connection failed: $e');
      _handleNetworkDisconnect();
      rethrow;
    }
  }

  /// Disconnect from WebSocket server (intentional - user action)
  Future<void> disconnect() async {
    _intentionalDisconnect = true;  // Mark as user-initiated
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    await _channel?.sink.close();
    _channel = null;
    
    // Clear stored connection info since this is intentional
    _userId = null;
    _wsUrl = null;
    _reconnectAttempts = 0;
    
    _handleDisconnect();
  }

  /// Send a generic message (for invalidate-user, etc.)
  void sendMessage(Map<String, dynamic> message) {
    _send(message);
  }

  /// Send a chat message
  void sendChatMessage(String content) {
    _send({
      'type': 'chat-message',
      'content': content,
    });
  }

  /// Notify room join
  void notifyJoinRoom(String roomId) {
    _send({
      'type': 'join-room',
      'roomId': roomId,
    });
  }

  /// Notify room leave
  void notifyLeaveRoom(String roomId) {
    _send({
      'type': 'leave-room',
      'roomId': roomId,
    });
  }

  /// Send speaking state
  void sendSpeakingState(bool isSpeaking) {
    _send({
      'type': 'speaking',
      'isSpeaking': isSpeaking,
    });
  }

  /// Send network status update (good, weak, disconnected)
  void sendNetworkStatus(String status) {
    _send({
      'type': 'network-status',
      'networkStatus': status,
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({
        'type': 'heartbeat',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      _messageController.add(data);

      switch (type) {
        case 'user-joined':
          if (data['user'] != null) {
            _userJoinedController.add(User.fromJson(data['user']));
          } else {
            _userJoinedController.add(User(
              id: data['userId'],
              name: data['userName'] ?? 'Unknown',
            ));
          }
          break;

        case 'user-left':
          _userLeftController.add(data['userId'] as String);
          break;

        case 'user-speaking':
          _userSpeakingController.add({
            'userId': data['userId'],
            'isSpeaking': data['isSpeaking'],
          });
          break;

        case 'user-state-changed':
          _userStateChangedController.add({
            'userId': data['userId'],
            'isMuted': data['isMuted'],
            'isDeafened': data['isDeafened'],
            'isSpeaking': data['isSpeaking'],
          });
          break;

        case 'user-network-status':
          _userNetworkStatusController.add({
            'userId': data['userId'],
            'userName': data['userName'],
            'networkStatus': data['networkStatus'],
          });
          break;

        case 'chat-message':
          _chatMessageController.add(ChatMessage.fromJson(data));
          break;

        case 'heartbeat-ack':
          // Connection is alive
          break;
      }
    } catch (e) {
      print('Error handling WebSocket message: $e');
    }
  }

  /// Handle intentional disconnect (user action - no reconnect)
  void _handleDisconnect() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }

  /// Handle network disconnect (unintentional - attempt reconnect)
  void _handleNetworkDisconnect() {
    if (!_isConnected && !_intentionalDisconnect) {
      // Already disconnected, might be in reconnect loop
      return;
    }
    
    final wasConnected = _isConnected;
    _isConnected = false;
    _channel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    if (wasConnected) {
      _connectionStateController.add(false);
      
      // Notify UI that current user is reconnecting
      _userNetworkStatusController.add({
        'userId': _userId,
        'userName': '',
        'networkStatus': 'reconnecting',
      });
    }
    
    // Attempt reconnection if not intentional and we have connection info
    if (!_intentionalDisconnect && _userId != null && _wsUrl != null) {
      _scheduleReconnect();
    }
  }

  /// Schedule a reconnection attempt with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached ($_maxReconnectAttempts)');
      _userNetworkStatusController.add({
        'userId': _userId,
        'userName': '',
        'networkStatus': 'disconnected',
      });
      return;
    }
    
    // Exponential backoff: 2s, 4s, 8s, 16s... capped at 30s
    final delay = Duration(
      milliseconds: (_baseReconnectDelayMs * (1 << _reconnectAttempts)).clamp(0, 30000),
    );
    _reconnectAttempts++;
    
    print('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _attemptReconnect);
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (_intentionalDisconnect || _userId == null || _wsUrl == null) {
      return;
    }
    
    print('Attempting reconnect (attempt $_reconnectAttempts)...');
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl!));
      await _channel!.ready;
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      
      // Re-register user
      _send({'type': 'register', 'userId': _userId});
      
      // Restart heartbeat
      _startHeartbeat();
      
      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('WebSocket error after reconnect: $error');
          _handleNetworkDisconnect();
        },
        onDone: () {
          print('WebSocket closed after reconnect');
          _handleNetworkDisconnect();
        },
      );
      
      print('Reconnected successfully!');
      _handleReconnect();
    } catch (e) {
      print('Reconnection attempt failed: $e');
      _scheduleReconnect();
    }
  }

  /// Call this after a successful reconnect (in connect)
  void _handleReconnect() {
    // Notify UI that current user is back to good
    _userNetworkStatusController.add({
      'userId': _userId,
      'userName': '',
      'networkStatus': 'good',
    });
  }

  void dispose() {
    _intentionalDisconnect = true;  // Prevent reconnect during dispose
    _reconnectTimer?.cancel();
    disconnect();
    _messageController.close();
    _userJoinedController.close();
    _userLeftController.close();
    _userSpeakingController.close();
    _userStateChangedController.close();
    _userNetworkStatusController.close();
    _chatMessageController.close();
    _connectionStateController.close();
  }
}
