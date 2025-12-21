import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/audio_provider.dart';

/// Voice Room Screen - active voice channel with chat
class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({super.key});

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  Room? _room;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _joinVoice();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _room ??= ModalRoute.of(context)?.settings.arguments as Room?;
  }

  Future<void> _joinVoice() async {
    if (_room == null) return;
    
    final auth = context.read<AuthProvider>();
    final audio = context.read<AudioProvider>();
    
    if (auth.currentUser != null) {
      await audio.joinVoice(
        _room!.id,
        auth.currentUser!.id,
        auth.currentUser!.name,
        roomName: _room!.name,
      );
    }
  }

  Future<void> _leaveRoom() async {
    final auth = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final audio = context.read<AudioProvider>();
    
    await audio.leaveVoice();
    await roomProvider.leaveRoom();
    auth.updateRoomId(null);
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    
    context.read<RoomProvider>().sendChatMessage(text);
    _chatController.clear();
    
    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = context.watch<RoomProvider>().currentRoom ?? _room;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leaveRoom,
        ),
        title: Row(
          children: [
            const Icon(Icons.volume_up, size: 20),
            const SizedBox(width: 8),
            Text(room?.name ?? 'Voice Channel'),
          ],
        ),
        actions: [
          // Connection status
          Consumer<AudioProvider>(
            builder: (context, audio, _) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: audio.isInVoiceChannel ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      audio.isInVoiceChannel ? Icons.check : Icons.sync,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      audio.isInVoiceChannel ? 'Connected' : 'Connecting...',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Users in voice
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade800,
            child: Consumer<RoomProvider>(
              builder: (context, roomProvider, _) {
                return SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: roomProvider.roomUsers.length,
                    itemBuilder: (context, index) {
                      return _buildUserAvatar(roomProvider.roomUsers[index]);
                    },
                  ),
                );
              },
            ),
          ),
          
          // Chat messages
          Expanded(
            child: Consumer<RoomProvider>(
              builder: (context, roomProvider, _) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: roomProvider.chatMessages.length,
                  itemBuilder: (context, index) {
                    return _buildChatMessage(roomProvider.chatMessages[index]);
                  },
                );
              },
            ),
          ),
          
          // Chat input
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade800,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Send a message...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade700,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.indigo),
                ),
              ],
            ),
          ),
          
          // Voice controls
          _buildVoiceControls(),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(User user) {
    // Network status colors
    Color networkIndicatorColor;
    IconData? networkIcon;
    switch (user.networkStatus) {
      case 'weak':
        networkIndicatorColor = Colors.orange;
        networkIcon = Icons.signal_cellular_alt_2_bar;
        break;
      case 'disconnected':
        networkIndicatorColor = Colors.red;
        networkIcon = Icons.signal_cellular_off;
        break;
      default:
        networkIndicatorColor = Colors.green;
        networkIcon = null; // Don't show icon for good connection
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: user.isSpeaking 
                      ? Colors.green.withOpacity(0.3) 
                      : Colors.grey.shade700,
                  shape: BoxShape.circle,
                  border: user.isSpeaking
                      ? Border.all(color: Colors.green, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Muted indicator (bottom right)
              if (user.isMuted)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off, size: 12, color: Colors.white),
                  ),
                ),
              // Network status indicator (top right) - only show if not good
              if (networkIcon != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: networkIndicatorColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(networkIcon, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              user.name,
              style: TextStyle(
                color: user.networkStatus == 'disconnected' 
                    ? Colors.red.shade300 
                    : Colors.grey.shade300,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessage(ChatMessage message) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            message.content,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isMe = message.userId == context.read<AuthProvider>().currentUser?.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (message.userName ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.userName ?? 'Unknown',
                      style: TextStyle(
                        color: isMe ? Colors.indigo.shade300 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Text(
                  message.content,
                  style: TextStyle(color: Colors.grey.shade300),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Consumer<AudioProvider>(
      builder: (context, audio, _) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          color: Colors.grey.shade800,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              _buildControlButton(
                icon: audio.isMuted ? Icons.mic_off : Icons.mic,
                label: audio.isMuted ? 'Unmute' : 'Mute',
                isActive: !audio.isMuted,
                activeColor: Colors.green,
                onPressed: audio.isInVoiceChannel ? audio.toggleMute : null,
              ),
              
              // Deafen button
              _buildControlButton(
                icon: audio.isDeafened ? Icons.headset_off : Icons.headset,
                label: audio.isDeafened ? 'Undeafen' : 'Deafen',
                isActive: !audio.isDeafened,
                activeColor: Colors.blue,
                onPressed: audio.isInVoiceChannel ? audio.toggleDeafen : null,
              ),
              
              // Leave button
              _buildControlButton(
                icon: Icons.call_end,
                label: 'Leave',
                isActive: true,
                activeColor: Colors.red,
                onPressed: _leaveRoom,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isActive 
                ? activeColor.withOpacity(0.2) 
                : Colors.grey.shade700.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(
              icon,
              color: isActive ? activeColor : Colors.grey,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
