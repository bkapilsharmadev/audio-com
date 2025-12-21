import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

/// Room Provider - manages rooms and room state
class RoomProvider extends ChangeNotifier {
  final ApiService _apiService;
  final WebSocketService _wsService;
  
  List<Room> _rooms = [];
  Room? _currentRoom;
  List<User> _roomUsers = [];
  List<ChatMessage> _chatMessages = [];
  bool _isLoading = false;
  String? _error;
  
  StreamSubscription? _userJoinedSub;
  StreamSubscription? _userLeftSub;
  StreamSubscription? _userStateSub;
  StreamSubscription? _chatMessageSub;
  StreamSubscription? _userSpeakingSub;
  StreamSubscription? _userNetworkStatusSub;
  StreamSubscription? _wsConnectionSub;  // WebSocket connection listener

  RoomProvider({
    ApiService? apiService,
    required WebSocketService wsService,
  })  : _apiService = apiService ?? ApiService(),
        _wsService = wsService {
    _setupWebSocketListeners();
    _setupConnectionListener();
  }

  // Getters
  List<Room> get rooms => _rooms;
  Room? get currentRoom => _currentRoom;
  List<User> get roomUsers => _roomUsers;
  List<ChatMessage> get chatMessages => _chatMessages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch all rooms
  Future<void> fetchRooms() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _rooms = await _apiService.getRooms();
      _isLoading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load rooms';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if room requires password
  Future<bool> roomRequiresPassword(String roomId) async {
    try {
      final result = await _apiService.checkRoomPassword(roomId);
      return result['requiresPassword'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Join a room
  Future<bool> joinRoom(String userId, String roomId, {String? password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.joinRoom(userId, roomId, password: password);
      
      // Load room details
      final room = await _apiService.getRoom(roomId);
      _currentRoom = room;
      
      // Load users in room
      await fetchRoomUsers(roomId);
      
      // Clear old chat messages
      _chatMessages = [];
      _chatMessages.add(ChatMessage.system('You joined ${room.name}'));
      
      // Notify WebSocket
      _wsService.notifyJoinRoom(roomId);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to join room';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Leave current room
  Future<void> leaveRoom() async {
    if (_currentRoom != null) {
      _wsService.notifyLeaveRoom(_currentRoom!.id);
    }
    
    _currentRoom = null;
    _roomUsers = [];
    _chatMessages = [];
    notifyListeners();
  }

  /// Fetch users in a room
  Future<void> fetchRoomUsers(String roomId) async {
    try {
      _roomUsers = await _apiService.getUsersInRoom(roomId);
      notifyListeners();
    } catch (e) {
      print('Failed to fetch room users: $e');
    }
  }

  /// Send a chat message
  void sendChatMessage(String content) {
    if (content.trim().isEmpty) return;
    _wsService.sendChatMessage(content);
  }

  /// Create a new room
  Future<Room?> createRoom({
    required String name,
    String? description,
    bool isPrivate = false,
    int maxUsers = 25,
    String? password,
  }) async {
    try {
      final room = await _apiService.createRoom(
        name: name,
        description: description,
        isPrivate: isPrivate,
        maxUsers: maxUsers,
        password: password,
      );
      
      await fetchRooms(); // Refresh room list
      return room;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to create room';
      notifyListeners();
      return null;
    }
  }

  void _setupWebSocketListeners() {
    _userJoinedSub = _wsService.onUserJoined.listen((user) {
      if (_currentRoom != null) {
        // Add user to list if not already there
        if (!_roomUsers.any((u) => u.id == user.id)) {
          _roomUsers.add(user);
          _chatMessages.add(ChatMessage.system('${user.name} joined'));
          notifyListeners();
          
          // Refresh room list to update user counts
          fetchRooms();
        }
      }
    });

    _userLeftSub = _wsService.onUserLeft.listen((userId) {
      final user = _roomUsers.firstWhere(
        (u) => u.id == userId,
        orElse: () => User(id: userId, name: 'User'),
      );
      _roomUsers.removeWhere((u) => u.id == userId);
      _chatMessages.add(ChatMessage.system('${user.name} left'));
      notifyListeners();
      
      // Refresh room list to update user counts
      fetchRooms();
    });

    _userStateSub = _wsService.onUserStateChanged.listen((data) {
      final userId = data['userId'] as String;
      final index = _roomUsers.indexWhere((u) => u.id == userId);
      if (index >= 0) {
        final user = _roomUsers[index];
        _roomUsers[index] = user.copyWith(
          isMuted: data['isMuted'] as bool?,
          isDeafened: data['isDeafened'] as bool?,
          isSpeaking: data['isSpeaking'] as bool?,
        );
        notifyListeners();
      }
    });

    _userSpeakingSub = _wsService.onUserSpeaking.listen((data) {
      final userId = data['userId'] as String;
      final isSpeaking = data['isSpeaking'] as bool;
      final index = _roomUsers.indexWhere((u) => u.id == userId);
      if (index >= 0) {
        _roomUsers[index] = _roomUsers[index].copyWith(isSpeaking: isSpeaking);
        notifyListeners();
      }
    });

    _chatMessageSub = _wsService.onChatMessage.listen((message) {
      _chatMessages.add(message);
      notifyListeners();
    });

    _userNetworkStatusSub = _wsService.onUserNetworkStatus.listen((data) {
      final userId = data['userId'] as String;
      final networkStatus = data['networkStatus'] as String;
      print('📡 Network status update received: userId=$userId status=$networkStatus');
      final index = _roomUsers.indexWhere((u) => u.id == userId);
      if (index >= 0) {
        print('📡 Updating user ${_roomUsers[index].name} status to $networkStatus');
        _roomUsers[index] = _roomUsers[index].copyWith(networkStatus: networkStatus);
        notifyListeners();
      } else {
        print('⚠️ User $userId not found in roomUsers (count: ${_roomUsers.length})');
      }
    });
  }

  /// Listen for WebSocket reconnection to refresh data
  void _setupConnectionListener() {
    _wsConnectionSub = _wsService.onConnectionStateChanged.listen((isConnected) {
      if (isConnected && _currentRoom != null) {
        // WebSocket reconnected - refresh room data to get current statuses
        print('📶 WebSocket reconnected - refreshing room data');
        fetchRoomUsers(_currentRoom!.id);
        fetchRooms();  // Also refresh room list for user counts
      }
    });
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _userJoinedSub?.cancel();
    _userLeftSub?.cancel();
    _userStateSub?.cancel();
    _chatMessageSub?.cancel();
    _userSpeakingSub?.cancel();
    _userNetworkStatusSub?.cancel();
    _wsConnectionSub?.cancel();
    _apiService.dispose();
    super.dispose();
  }
}

