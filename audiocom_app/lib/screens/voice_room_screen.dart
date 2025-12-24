import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:livekit_client/livekit_client.dart' hide Room, ChatMessage;
import '../models/room.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/audio_provider.dart';
import '../services/livekit_service.dart';

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
  bool _isLeaving = false;  // Prevent double-leave

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
    if (_isLeaving) return;  // Prevent double-leave
    _isLeaving = true;
    
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return PopScope(
      canPop: false,  // Intercept back button
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveRoom();  // Properly leave room before popping
      },
      child: Scaffold(
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
              Color statusColor;
              IconData statusIcon;
              String statusText;
              
              if (audio.isReconnecting) {
                statusColor = Colors.orange;
                statusIcon = Icons.wifi_off;
                statusText = 'Reconnecting...';
              } else if (audio.isInVoiceChannel) {
                statusColor = Colors.green;
                statusIcon = Icons.check;
                statusText = 'Connected';
              } else if (audio.error != null && audio.error!.contains('network')) {
                statusColor = Colors.red;
                statusIcon = Icons.signal_wifi_off;
                statusText = 'Disconnected';
              } else {
                statusColor = Colors.orange;
                statusIcon = Icons.sync;
                statusText = 'Connecting...';
              }
              
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioProvider>(
        builder: (context, audio, _) {
          final hasVideo = audio.isCameraEnabled || audio.isScreenShareEnabled ||
              _hasRemoteVideo(audio);
          
          return Column(
            children: [
              // Video grid (when video is active)
              if (hasVideo)
                Expanded(
                  flex: 2,
                  child: _buildVideoGrid(audio),
                ),
              
              // Users in voice (smaller when video active)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade800,
                child: Consumer<RoomProvider>(
                  builder: (context, roomProvider, _) {
                    return SizedBox(
                      height: hasVideo ? 60 : 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: roomProvider.roomUsers.length,
                        itemBuilder: (context, index) {
                          return _buildUserAvatar(roomProvider.roomUsers[index], compact: hasVideo);
                        },
                      ),
                    );
                  },
                ),
              ),
              
              // Chat messages (collapsible when video active)
              if (!hasVideo)
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
                )
              else
                // Mini chat when video is active
                Expanded(
                  flex: 1,
                  child: Consumer<RoomProvider>(
                    builder: (context, roomProvider, _) {
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: roomProvider.chatMessages.length,
                        itemBuilder: (context, index) {
                          return _buildChatMessage(roomProvider.chatMessages[index], compact: true);
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
              
              // Voice/Video controls
              _buildVoiceControls(),
              
              // Safe area padding for system navigation
              SizedBox(height: bottomPadding),
            ],
          );
        },
      ),
    ),  // Close PopScope
    );
  }

  /// Check if any remote participant has video
  bool _hasRemoteVideo(AudioProvider audio) {
    final room = audio.livekitService.room;
    if (room == null) return false;
    
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) {
          return true;
        }
      }
    }
    return false;
  }

  String? _maximizedTrackId; // State to track maximized video

  /// Build the video grid
  Widget _buildVideoGrid(AudioProvider audio) {
    final room = audio.livekitService.room;
    if (room == null) return const SizedBox.shrink();

    final List<Widget> videoTiles = [];
    final List<VideoTrack> tracks = [];
    final List<String> names = [];
    final List<bool> isLocals = [];
    final List<bool> isFronts = [];
    final List<bool> isScreenShares = [];

    // Helper to add track data
    void addTrack(VideoTrack track, String name, {bool isLocal = false, bool isFront = false, bool isScreenShare = false}) {
      tracks.add(track);
      names.add(name);
      isLocals.add(isLocal);
      isFronts.add(isFront);
      isScreenShares.add(isScreenShare);
    }

    // Local video
    final localParticipant = room.localParticipant;
    if (localParticipant != null) {
      for (final pub in localParticipant.videoTrackPublications) {
        if (pub.track != null && pub.source == TrackSource.camera) {
          addTrack(pub.track as VideoTrack, 'You', isLocal: true, isFront: audio.isFrontCamera);
        }
      }
      for (final pub in localParticipant.videoTrackPublications) {
        if (pub.track != null && pub.source == TrackSource.screenShareVideo) {
          addTrack(pub.track as VideoTrack, 'Your Screen', isLocal: true, isScreenShare: true);
        }
      }
    }

    // Remote videos
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) {
          final isScreen = pub.source == TrackSource.screenShareVideo;
          addTrack(pub.track as VideoTrack, 
            isScreen ? '${participant.identity}\'s Screen' : participant.identity,
            isScreenShare: isScreen);
        }
      }
    }

    if (tracks.isEmpty) return const SizedBox.shrink();

    // build tiles
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      // Use track.sid or fallback to index if null/empty
      final trackId = track.sid ?? 'track_$i';
      
      videoTiles.add(GestureDetector(
        onTap: () {
          setState(() {
            _maximizedTrackId = (_maximizedTrackId == trackId) ? null : trackId;
          });
        },
        child: _buildVideoTile(
          track,
          names[i],
          isLocal: isLocals[i],
          isFront: isFronts[i],
          isScreenShare: isScreenShares[i],
          showMaximizeIcon: true,
          isMaximized: _maximizedTrackId == trackId,
        ),
      ));
    }

    // Maximized Layout
    if (_maximizedTrackId != null) {
      // Find the maximized tile index
      int maxIndex = -1;
      for (int i = 0; i < tracks.length; i++) {
        if ((tracks[i].sid ?? 'track_$i') == _maximizedTrackId) {
          maxIndex = i;
          break;
        }
      }
      
      // If track not found (e.g. user left), reset
      if (maxIndex == -1) {
        // Schedule reset for next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _maximizedTrackId = null);
        });
        return const SizedBox.shrink(); // Temporary
      }

      final maximizedTile = videoTiles[maxIndex];
      final otherTiles = List<Widget>.from(videoTiles)..removeAt(maxIndex);

      return Column(
        children: [
          // Maximized Video
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: maximizedTile,
            ),
          ),
          
          // Strip of other videos
          if (otherTiles.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(4),
                itemCount: otherTiles.length,
                separatorBuilder: (c, i) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 160, // Fixed aspect ratio approx
                    child: otherTiles[index],
                  );
                },
              ),
            ),
        ],
      );
    }

    // Standard Grid Layout
    if (videoTiles.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: videoTiles.first,
      );
    }

    return GridView.count(
      crossAxisCount: videoTiles.length <= 4 ? 2 : 3,
      padding: const EdgeInsets.all(4),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: videoTiles,
    );
  }

  /// Build a single video tile
  Widget _buildVideoTile(VideoTrack track, String name, {
    bool isLocal = false,
    bool isFront = true,
    bool isScreenShare = false,
    bool showMaximizeIcon = false,
    bool isMaximized = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isMaximized ? Colors.indigoAccent : Colors.grey.shade700, width: isMaximized ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoTrackRenderer(
              track,
              fit: isScreenShare ? VideoViewFit.contain : VideoViewFit.cover,
              mirrorMode: isLocal && !isScreenShare && isFront 
                  ? VideoViewMirrorMode.mirror 
                  : VideoViewMirrorMode.off,
            ),
            // Name overlay
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            // Flip camera button for local video
            if (isLocal && !isScreenShare)
              Positioned(
                right: 8,
                top: 8,
                child: GestureDetector(
                  onTap: () => context.read<AudioProvider>().flipCamera(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 20),
                  ),
                ),
              ),
              
            // Maximize/Minimize Icon Overlay
            if (showMaximizeIcon)
              Positioned.fill(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: isMaximized ? 0.0 : 0.0, // Hidden generally, can be visible on hover if generic desktop
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white.withOpacity(0.7),
                      size: 48,
                    ),
                  ),
                ),
              ),
              
            // Small maximize indicator in corner
             if (showMaximizeIcon && !isLocal) // Don't clutter local too much
              Positioned(
                right: 8,
                top: 8,
                 child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, 
                      color: Colors.white, 
                      size: 16
                    ),
                  ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(User user, {bool compact = false}) {
    final avatarSize = compact ? 40.0 : 48.0;
    final fontSize = compact ? 9.0 : 11.0;
    final iconSize = compact ? 10.0 : 12.0;
    
    // Network status colors
    Color networkIndicatorColor;
    IconData? networkIcon;
    switch (user.networkStatus) {
      case 'weak':
        networkIndicatorColor = Colors.orange;
        networkIcon = Icons.signal_cellular_alt_2_bar;
        break;
      case 'reconnecting':
      case 'disconnected':
        // Network issue - user is disconnected or trying to reconnect (red wifi icon)
        networkIndicatorColor = Colors.red;
        networkIcon = Icons.wifi_off;
        break;
      default:
        networkIndicatorColor = Colors.green;
        networkIcon = null; // Don't show icon for good connection
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // Animated speaking ring
              if (user.isSpeaking)
                _SpeakingRing(
                  size: avatarSize,
                  child: _buildAvatarCircle(user, size: avatarSize),
                )
              else
                _buildAvatarCircle(user, size: avatarSize),
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
                    child: Icon(Icons.mic_off, size: iconSize, color: Colors.white),
                  ),
                ),
              // Deafened indicator (bottom left when muted, bottom right when only deafened)
              if (user.isDeafened)
                Positioned(
                  left: user.isMuted ? 0 : null,  // Move to left if also muted
                  right: user.isMuted ? null : 0, // Stay right if only deafened
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.headset_off, size: iconSize, color: Colors.white),
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
                    child: Icon(networkIcon, size: iconSize, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: compact ? 50 : 60,
            child: Text(
              user.name,
              style: TextStyle(
                color: (user.networkStatus == 'disconnected' || user.networkStatus == 'reconnecting')
                    ? Colors.red.shade300 
                    : Colors.grey.shade300,
                fontSize: fontSize,
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

  Widget _buildChatMessage(ChatMessage message, {bool compact = false}) {
    if (message.isSystem) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
        child: Center(
          child: Text(
            message.content,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: compact ? 10 : 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isMe = message.userId == context.read<AuthProvider>().currentUser?.id;

    if (compact) {
      // Compact inline format for video mode
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${message.userName ?? 'Unknown'}: ',
                style: TextStyle(
                  color: isMe ? Colors.indigo.shade300 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              TextSpan(
                text: message.content,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

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
        // Get icon for current audio output
        IconData audioOutputIcon;
        String audioOutputLabel;
        switch (audio.currentAudioOutput) {
          case AudioOutputDevice.speaker:
            audioOutputIcon = Icons.volume_up;
            audioOutputLabel = 'Speaker';
            break;
          case AudioOutputDevice.earpiece:
            audioOutputIcon = Icons.phone_in_talk;
            audioOutputLabel = 'Earpiece';
            break;
          case AudioOutputDevice.bluetooth:
            audioOutputIcon = Icons.bluetooth_audio;
            audioOutputLabel = 'Bluetooth';
            break;
          case AudioOutputDevice.wired:
            audioOutputIcon = Icons.headset;
            audioOutputLabel = 'Headset';
            break;
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          color: Colors.grey.shade800,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mute button
                _buildControlButton(
                  icon: audio.isMuted ? Icons.mic_off : Icons.mic,
                  label: audio.isMuted ? 'Unmute' : 'Mute',
                  isActive: !audio.isMuted,
                  activeColor: Colors.green,
                  onPressed: audio.isInVoiceChannel ? audio.toggleMute : null,
                ),
                const SizedBox(width: 8),
                
                // Camera button
                _buildControlButton(
                  icon: audio.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                  label: audio.isCameraEnabled ? 'Cam Off' : 'Cam On',
                  isActive: audio.isCameraEnabled,
                  activeColor: Colors.teal,
                  onPressed: audio.isInVoiceChannel ? audio.toggleCamera : null,
                ),
                const SizedBox(width: 8),
                
                // Video quality button (only show when camera is on)
                if (audio.isCameraEnabled)
                  ...[
                    _buildControlButton(
                      icon: _getQualityIcon(audio.currentVideoQuality),
                      label: _getQualityLabel(audio.currentVideoQuality),
                      isActive: true,
                      activeColor: Colors.cyan,
                      onPressed: audio.isInVoiceChannel ? () => _showVideoQualityPicker(audio) : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                
                // Screen share button
                _buildControlButton(
                  icon: audio.isScreenShareEnabled ? Icons.stop_screen_share : Icons.screen_share,
                  label: audio.isScreenShareEnabled ? 'Stop' : 'Share',
                  isActive: audio.isScreenShareEnabled,
                  activeColor: Colors.orange,
                  onPressed: audio.isInVoiceChannel ? audio.toggleScreenShare : null,
                ),
                const SizedBox(width: 8),
                
                // Audio output button
                _buildControlButton(
                  icon: audioOutputIcon,
                  label: audioOutputLabel,
                  isActive: true,
                  activeColor: Colors.purple,
                  onPressed: audio.isInVoiceChannel ? audio.cycleAudioOutput : null,
                ),
                const SizedBox(width: 8),
                
                // Deafen button
                _buildControlButton(
                  icon: audio.isDeafened ? Icons.headset_off : Icons.headset_mic,
                  label: audio.isDeafened ? 'Undeaf' : 'Deafen',
                  isActive: !audio.isDeafened,
                  activeColor: Colors.blue,
                  onPressed: audio.isInVoiceChannel ? audio.toggleDeafen : null,
                ),
                const SizedBox(width: 8),
                
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
          width: 48,
          height: 48,
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
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// Get icon for video quality
  IconData _getQualityIcon(VideoQualityPreset quality) {
    switch (quality) {
      case VideoQualityPreset.low:
        return Icons.sd;
      case VideoQualityPreset.medium:
        return Icons.hd;
      case VideoQualityPreset.high:
        return Icons.four_k;
    }
  }

  /// Get label for video quality
  String _getQualityLabel(VideoQualityPreset quality) {
    switch (quality) {
      case VideoQualityPreset.low:
        return 'Low';
      case VideoQualityPreset.medium:
        return 'Med';
      case VideoQualityPreset.high:
        return 'HD';
    }
  }

  /// Show video quality picker
  void _showVideoQualityPicker(AudioProvider audio) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Video Quality',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lower quality = less battery usage & data',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildQualityOption(
                audio,
                VideoQualityPreset.low,
                'Low',
                '240p @ 15fps • Battery saver',
                Icons.battery_saver,
              ),
              _buildQualityOption(
                audio,
                VideoQualityPreset.medium,
                'Medium',
                '360p @ 24fps • Balanced',
                Icons.speed,
              ),
              _buildQualityOption(
                audio,
                VideoQualityPreset.high,
                'HD',
                '720p @ 30fps • Best quality',
                Icons.high_quality,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// Build a quality option tile
  Widget _buildQualityOption(
    AudioProvider audio,
    VideoQualityPreset quality,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = audio.currentVideoQuality == quality;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors.cyan : Colors.grey.shade400,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.cyan : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.cyan)
          : null,
      onTap: () {
        audio.setVideoQuality(quality);
        Navigator.pop(context);
      },
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildAvatarCircle(User user, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade700,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Animated speaking ring widget
class _SpeakingRing extends StatefulWidget {
  final Widget child;
  final double size;
  
  const _SpeakingRing({required this.child, this.size = 48});

  @override
  State<_SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<_SpeakingRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _opacityAnimation = Tween<double>(begin: 0.8, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outerSize = widget.size + 4;
    final innerSize = widget.size + 2;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Animated outer ring
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.green.withOpacity(_opacityAnimation.value),
                    width: 3,
                  ),
                ),
              ),
            ),
            // Inner green border
            Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: ClipOval(child: widget.child),
            ),
          ],
        );
      },
    );
  }
}
