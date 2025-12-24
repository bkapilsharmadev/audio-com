import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:livekit_client/livekit_client.dart';
import 'foreground_service.dart';
import 'screen_share_helper.dart';

/// Audio output device types
enum AudioOutputDevice {
  speaker,    // External speaker (loudspeaker)
  earpiece,   // Phone earpiece (in-ear)
  bluetooth,  // Bluetooth headset
  wired,      // Wired headset
}

/// Video quality presets (renamed to avoid conflict with livekit)
enum VideoQualityPreset {
  low,     // 320x240 @ 15fps, 150kbps - Battery saver
  medium,  // 640x480 @ 24fps, 500kbps - Balanced  
  high,    // 1280x720 @ 30fps, 1500kbps - HD quality
}

/// Get camera capture options for a quality preset
CameraCaptureOptions getCameraCaptureForQuality(VideoQualityPreset quality) {
  switch (quality) {
    case VideoQualityPreset.low:
      return const CameraCaptureOptions(
        maxFrameRate: 15,
        params: VideoParametersPresets.h180_169,
      );
    case VideoQualityPreset.medium:
      return const CameraCaptureOptions(
        maxFrameRate: 24,
        params: VideoParametersPresets.h360_169,
      );
    case VideoQualityPreset.high:
      return const CameraCaptureOptions(
        maxFrameRate: 30,
        params: VideoParametersPresets.h720_169,
      );
  }
}

/// LiveKit Service for audio/video communication
class LivekitService {
  Room? _room;
  LocalParticipant? _localParticipant;
  EventsListener<RoomEvent>? _roomListener;
  
  bool _isMicEnabled = false;
  bool _isCameraEnabled = false;
  bool _isScreenShareEnabled = false;
  bool _isConnected = false;
  int _currentBitrate = 32000; // Current bitrate in bps
  AudioOutputDevice _currentAudioOutput = AudioOutputDevice.speaker;
  List<MediaDevice> _availableAudioOutputs = [];
  List<MediaDevice> _availableCameras = [];
  String? _selectedCameraId;
  bool _isFrontCamera = true;
  VideoQualityPreset _currentVideoQuality = VideoQualityPreset.low; // Default to low for battery

  // Event streams
  final _connectionStateController = StreamController<bool>.broadcast();
  final _reconnectingController = StreamController<bool>.broadcast();
  final _participantJoinedController = StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController = StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _trackSubscribedController = StreamController<RemoteTrackPublication>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _audioOutputChangedController = StreamController<AudioOutputDevice>.broadcast();
  final _videoStateChangedController = StreamController<bool>.broadcast();
  final _screenShareChangedController = StreamController<bool>.broadcast();

  // Public streams
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;
  Stream<bool> get onReconnecting => _reconnectingController.stream;
  Stream<RemoteParticipant> get onParticipantJoined => _participantJoinedController.stream;
  Stream<RemoteParticipant> get onParticipantLeft => _participantLeftController.stream;
  Stream<Map<String, dynamic>> get onSpeakingChanged => _speakingChangedController.stream;
  Stream<RemoteTrackPublication> get onTrackSubscribed => _trackSubscribedController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<AudioOutputDevice> get onAudioOutputChanged => _audioOutputChangedController.stream;
  Stream<bool> get onVideoStateChanged => _videoStateChangedController.stream;
  Stream<bool> get onScreenShareChanged => _screenShareChangedController.stream;

  // Getters
  bool get isConnected => _isConnected;
  bool get isMicEnabled => _isMicEnabled;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isScreenShareEnabled => _isScreenShareEnabled;
  int get currentBitrate => _currentBitrate;
  Room? get room => _room;
  LocalParticipant? get localParticipant => _localParticipant;
  AudioOutputDevice get currentAudioOutput => _currentAudioOutput;
  List<MediaDevice> get availableAudioOutputs => _availableAudioOutputs;
  List<MediaDevice> get availableCameras => _availableCameras;
  bool get isFrontCamera => _isFrontCamera;
  VideoQualityPreset get currentVideoQuality => _currentVideoQuality;
  
  List<RemoteParticipant> get remoteParticipants {
    return _room?.remoteParticipants.values.toList() ?? [];
  }

  /// Connect to LiveKit room with configurable bitrate
  Future<void> connect(String url, String token, {int audioBitrateBps = 32000}) async {
    _currentBitrate = audioBitrateBps;
    
    try {
      // Create room with audio-only options
      // Opus codec bitrate settings - configurable
      _room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true,  // Discontinuous transmission for bandwidth saving
            audioBitrate: audioBitrateBps,  // Configurable bitrate (Opus range: 6-510 kbps)
          ),
          defaultVideoPublishOptions: const VideoPublishOptions(
            simulcast: false,
          ),
        ),
      );

      // Set up event listener
      _roomListener = _room!.createListener();
      _setupRoomListeners();

      // Connect to room
      await _room!.connect(
        url,
        token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: false), // Start with mic off
          camera: TrackOption(enabled: false),     // No camera (audio only)
        ),
      );

      _localParticipant = _room!.localParticipant;
      _isConnected = true;
      _connectionStateController.add(true);
      
      print('✓ Connected to LiveKit room (bitrate: ${audioBitrateBps ~/ 1000} kbps)');

      print('✓ Connected to LiveKit room');
    } catch (e) {
      print('✗ Failed to connect to LiveKit: $e');
      _errorController.add('Failed to connect: $e');
      rethrow;
    }
  }

  /// Enable/disable microphone
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_localParticipant == null) {
      print('⚠ Cannot ${enabled ? "enable" : "disable"} microphone: no local participant');
      return;
    }

    try {
      await _localParticipant!.setMicrophoneEnabled(enabled);
      _isMicEnabled = enabled;
      print('Microphone ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      print('Failed to ${enabled ? "enable" : "disable"} microphone: $e');
      _errorController.add('Microphone error: $e');
      
      // If enabling failed, reset the state
      if (enabled) {
        _isMicEnabled = false;
      }
    }
  }

  /// Toggle microphone
  Future<void> toggleMicrophone() async {
    await setMicrophoneEnabled(!_isMicEnabled);
  }

  /// Enable/disable camera with current video quality
  Future<void> setCameraEnabled(bool enabled) async {
    if (_localParticipant == null) {
      print('⚠ Cannot ${enabled ? "enable" : "disable"} camera: no local participant');
      return;
    }

    try {
      if (enabled) {
        // Enable camera with quality settings
        await _localParticipant!.setCameraEnabled(
          true,
          cameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: getCameraCaptureForQuality(_currentVideoQuality).maxFrameRate,
            params: getCameraCaptureForQuality(_currentVideoQuality).params,
          ),
        );
      } else {
        await _localParticipant!.setCameraEnabled(false);
      }
      _isCameraEnabled = enabled;
      _videoStateChangedController.add(enabled);
      print('Camera ${enabled ? "enabled" : "disabled"} (quality: ${_currentVideoQuality.name})');
    } catch (e) {
      print('Failed to ${enabled ? "enable" : "disable"} camera: $e');
      _errorController.add('Camera error: $e');
      
      if (enabled) {
        _isCameraEnabled = false;
      }
    }
  }

  /// Set video quality (low/medium/high)
  Future<void> setVideoQuality(VideoQualityPreset quality) async {
    if (_currentVideoQuality == quality) return;
    
    final previousQuality = _currentVideoQuality;
    _currentVideoQuality = quality;
    print('🎥 Video quality changing: ${previousQuality.name} -> ${quality.name}');
    
    // If camera is enabled, restart with new quality
    if (_isCameraEnabled && _localParticipant != null) {
      try {
        // Get the current camera track
        final videoPublication = _localParticipant!.videoTrackPublications
            .where((pub) => pub.source == TrackSource.camera)
            .firstOrNull;
        
        if (videoPublication?.track != null) {
          final videoTrack = videoPublication!.track as LocalVideoTrack;
          final captureOptions = getCameraCaptureForQuality(quality);
          
          print('🎥 Restarting camera with: ${captureOptions.params.dimensions.width}x${captureOptions.params.dimensions.height} @ ${captureOptions.maxFrameRate}fps');
          
          // Restart track with new options
          await videoTrack.restartTrack(captureOptions);
          
          print('✅ Camera quality changed to ${quality.name}');
        } else {
          // No active track, re-enable with new quality
          print('🎥 No active track, re-enabling camera...');
          await _localParticipant!.setCameraEnabled(false);
          await Future.delayed(const Duration(milliseconds: 200));
          await _localParticipant!.setCameraEnabled(
            true,
            cameraCaptureOptions: getCameraCaptureForQuality(quality),
          );
          print('✅ Camera re-enabled with ${quality.name} quality');
        }
        
        // Notify UI to update
        _videoStateChangedController.add(true);
      } catch (e) {
        print('❌ Failed to change video quality: $e');
        _errorController.add('Failed to change quality: $e');
        // Revert quality on failure
        _currentVideoQuality = previousQuality;
      }
    }
  }

  /// Cycle through video quality presets
  void cycleVideoQuality() {
    switch (_currentVideoQuality) {
      case VideoQualityPreset.low:
        setVideoQuality(VideoQualityPreset.medium);
        break;
      case VideoQualityPreset.medium:
        setVideoQuality(VideoQualityPreset.high);
        break;
      case VideoQualityPreset.high:
        setVideoQuality(VideoQualityPreset.low);
        break;
    }
  }

  /// Toggle camera
  Future<void> toggleCamera() async {
    await setCameraEnabled(!_isCameraEnabled);
  }

  /// Switch between front and back camera
  Future<void> flipCamera() async {
    if (_localParticipant == null || !_isCameraEnabled) return;

    try {
      // Get available cameras
      final allDevices = await Hardware.instance.enumerateDevices();
      _availableCameras = allDevices.where((d) => d.kind == 'videoinput').toList();
      
      if (_availableCameras.length < 2) {
        print('Only one camera available');
        return;
      }

      // Find the video track and switch camera
      final videoTrack = _localParticipant!.videoTrackPublications.firstOrNull?.track;
      if (videoTrack != null && videoTrack is LocalVideoTrack) {
        // Switch camera using LiveKit's built-in method
        await videoTrack.restartTrack();
        _isFrontCamera = !_isFrontCamera;
        print('Camera flipped to ${_isFrontCamera ? "front" : "back"}');
      }
    } catch (e) {
      print('Failed to flip camera: $e');
      _errorController.add('Failed to switch camera: $e');
    }
  }

  /// Start screen sharing
  Future<bool> startScreenShare() async {
    if (_localParticipant == null) {
      print('⚠ Cannot start screen share: no local participant');
      return false;
    }

    // Android 14+: Start dedicated native foreground service
    if (Platform.isAndroid) {
      print('🚀 Starting native screen share service...');
      await ScreenShareHelper.startService();
      // Short delay to ensure service is fully registered
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      // Request screen capture permission and create screen track
      await _localParticipant!.setScreenShareEnabled(true, captureScreenAudio: true);
      _isScreenShareEnabled = true;
      _screenShareChangedController.add(true);
      print('✅ Screen sharing started');
      return true;
    } on PlatformException catch (e) {
      print('❌ Platform error starting screen share: $e');
      _errorController.add('Screen share error: ${e.message}');
      
      // Stop service on failure
      if (Platform.isAndroid) {
        await ScreenShareHelper.stopService();
      }
      return false;
    } catch (e) {
      print('❌ Failed to start screen share: $e');
      _errorController.add('Screen share error: $e');
       
      // Stop service on failure
      if (Platform.isAndroid) {
        await ScreenShareHelper.stopService();
      }
      return false;
    }
  }

  /// Stop screen sharing
  Future<void> stopScreenShare() async {
    if (_localParticipant == null) return;

    try {
      await _localParticipant!.setScreenShareEnabled(false);
      _isScreenShareEnabled = false;
      _screenShareChangedController.add(false);
      print('Screen sharing stopped');
      
      // Stop native service
      if (Platform.isAndroid) {
         await ScreenShareHelper.stopService();
      }
    } catch (e) {
      print('Failed to stop screen share: $e');
      _errorController.add('Failed to stop screen share: $e');
    }
  }

  /// Toggle screen sharing
  Future<void> toggleScreenShare() async {
    if (_isScreenShareEnabled) {
      await stopScreenShare();
    } else {
      await startScreenShare();
    }
  }

  /// Set audio output volume for a participant
  void setParticipantVolume(String participantId, double volume) {
    final participant = _room?.remoteParticipants[participantId];
    if (participant != null) {
      for (final track in participant.audioTrackPublications) {
        if (track.track != null) {
          // Volume is typically controlled at the track level
          // LiveKit handles this automatically
        }
      }
    }
  }

  bool _isDeafened = false;
  bool get isDeafened => _isDeafened;
  Set<String> _previousSpeakers = {}; // Track previous speakers for change detection

  /// Set deafened state - mutes/unmutes all incoming audio
  Future<void> setDeafened(bool deafened) async {
    if (_room == null) return;
    
    _isDeafened = deafened;
    
    try {
      // Iterate through all remote participants and mute/unmute their audio tracks
      for (final participant in _room!.remoteParticipants.values) {
        for (final publication in participant.audioTrackPublications) {
          // Use disable/enable on RemoteTrackPublication to control subscription
          // When disabled, audio from this track won't play
          if (deafened) {
            await publication.disable();
          } else {
            await publication.enable();
          }
        }
      }
      print('Audio ${deafened ? "deafened (disabled remote tracks)" : "undeafened (enabled remote tracks)"}');
    } catch (e) {
      print('Failed to set deafen state: $e');
      _errorController.add('Deafen error: $e');
    }
  }

  /// Get available audio output devices
  Future<void> refreshAudioDevices() async {
    try {
      final allDevices = await Hardware.instance.enumerateDevices();
      _availableAudioOutputs = allDevices.where((d) => d.kind == 'audiooutput').toList();
      print('Available audio outputs: ${_availableAudioOutputs.map((d) => d.label).toList()}');
    } catch (e) {
      print('Failed to enumerate audio devices: $e');
    }
  }

  /// Set audio output to speaker (loudspeaker)
  Future<void> setSpeakerOutput() async {
    try {
      await Hardware.instance.setSpeakerphoneOn(true);
      _currentAudioOutput = AudioOutputDevice.speaker;
      _audioOutputChangedController.add(_currentAudioOutput);
      print('Audio output: Speaker (loudspeaker)');
    } catch (e) {
      print('Failed to set speaker output: $e');
      _errorController.add('Failed to switch to speaker: $e');
    }
  }

  /// Set audio output to earpiece (phone speaker)
  Future<void> setEarpieceOutput() async {
    try {
      await Hardware.instance.setSpeakerphoneOn(false);
      _currentAudioOutput = AudioOutputDevice.earpiece;
      _audioOutputChangedController.add(_currentAudioOutput);
      print('Audio output: Earpiece');
    } catch (e) {
      print('Failed to set earpiece output: $e');
      _errorController.add('Failed to switch to earpiece: $e');
    }
  }

  /// Set audio output device by type
  Future<void> setAudioOutput(AudioOutputDevice device) async {
    switch (device) {
      case AudioOutputDevice.speaker:
        await setSpeakerOutput();
        break;
      case AudioOutputDevice.earpiece:
        await setEarpieceOutput();
        break;
      case AudioOutputDevice.bluetooth:
      case AudioOutputDevice.wired:
        // For bluetooth/wired, we just need to turn off speakerphone
        // The system will route to the connected device automatically
        await setEarpieceOutput();
        _currentAudioOutput = device;
        _audioOutputChangedController.add(_currentAudioOutput);
        print('Audio output: ${device.name}');
        break;
    }
  }

  /// Cycle through audio outputs: Speaker -> Earpiece -> (Bluetooth if available) -> Speaker
  Future<void> cycleAudioOutput() async {
    await refreshAudioDevices();
    
    // Check if bluetooth/wired headset is connected
    final hasBluetoothOrWired = _availableAudioOutputs.any((d) => 
      d.label.toLowerCase().contains('bluetooth') || 
      d.label.toLowerCase().contains('headset') ||
      d.label.toLowerCase().contains('headphone'));
    
    switch (_currentAudioOutput) {
      case AudioOutputDevice.speaker:
        await setEarpieceOutput();
        break;
      case AudioOutputDevice.earpiece:
        if (hasBluetoothOrWired) {
          // Route to bluetooth/wired (system handles it when speakerphone is off)
          _currentAudioOutput = AudioOutputDevice.bluetooth;
          _audioOutputChangedController.add(_currentAudioOutput);
          print('Audio output: Bluetooth/Wired headset');
        } else {
          await setSpeakerOutput();
        }
        break;
      case AudioOutputDevice.bluetooth:
      case AudioOutputDevice.wired:
        await setSpeakerOutput();
        break;
    }
  }

  /// Get icon for current audio output
  String getAudioOutputIcon() {
    switch (_currentAudioOutput) {
      case AudioOutputDevice.speaker:
        return 'volume_up';
      case AudioOutputDevice.earpiece:
        return 'phone_in_talk';
      case AudioOutputDevice.bluetooth:
        return 'bluetooth_audio';
      case AudioOutputDevice.wired:
        return 'headset';
    }
  }

  /// Disconnect from room
  Future<void> disconnect() async {
    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;
    _isConnected = false;
    _isDeafened = false;  // Reset deafen state so new room starts fresh
    _previousSpeakers = {}; // Reset speaking tracking
    _isFrontCamera = true;
    
    _roomListener?.dispose();
    _roomListener = null;
    
    await _room?.disconnect();
    _room = null;
    _localParticipant = null;
    
    _connectionStateController.add(false);
    print('Disconnected from LiveKit room');
  }

  void _setupRoomListeners() {
    _roomListener
      ?..on<RoomDisconnectedEvent>((event) {
        print('Room disconnected: ${event.reason}');
        _isConnected = false;
        _connectionStateController.add(false);
      })
      ..on<RoomReconnectingEvent>((event) async {
        print('⚠ Room reconnecting...');
        _reconnectingController.add(true);
        
        // Unpublish all local audio tracks to prevent "track is null" errors
        // when LiveKit tries to rePublishAllTracks internally.
        // We'll re-publish them after reconnection if needed.
        if (_localParticipant != null) {
          try {
            final audioTracks = _localParticipant!.audioTrackPublications.toList();
            for (final publication in audioTracks) {
              if (publication.track != null) {
                print('🔄 Unpublishing track before reconnect: ${publication.sid}');
                await _localParticipant!.removePublishedTrack(publication.sid);
              }
            }
          } catch (e) {
            print('⚠ Error unpublishing tracks during reconnect: $e');
          }
        }
        
        _localParticipant = _room?.localParticipant;
      })
      ..on<RoomReconnectedEvent>((event) async {
        print('✓ Room reconnected');
        _isConnected = true;
        _reconnectingController.add(false);
        _connectionStateController.add(true);
        
        // Update local participant reference
        _localParticipant = _room?.localParticipant;
        
        // Re-establish microphone state after reconnection
        // Since we unpublished tracks during reconnecting, we need to re-enable if it was on
        if (_isMicEnabled && _localParticipant != null) {
          try {
            // Small delay to ensure connection is fully established
            await Future.delayed(const Duration(milliseconds: 500));
            await _localParticipant!.setMicrophoneEnabled(true);
            print('✓ Microphone re-enabled after reconnection');
          } catch (e) {
            print('⚠ Failed to re-enable microphone after reconnection: $e');
            _errorController.add('Failed to re-enable microphone: $e');
          }
        }
      })
      ..on<ParticipantConnectedEvent>((event) {
        print('Participant joined: ${event.participant.identity}');
        _participantJoinedController.add(event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        print('Participant left: ${event.participant.identity}');
        _participantLeftController.add(event.participant);
      })
      ..on<TrackSubscribedEvent>((event) {
        print('Track subscribed: ${event.publication.sid}');
        _trackSubscribedController.add(event.publication);
        
        // If we're currently deafened, disable new audio tracks immediately
        if (_isDeafened && event.publication.kind == TrackType.AUDIO) {
          event.publication.disable();
          print('New track auto-disabled (deafened)');
        }
      })
      ..on<TrackUnsubscribedEvent>((event) {
        print('Track unsubscribed: ${event.publication.sid}');
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        // Get current speaker identities
        final currentSpeakers = event.speakers.map((s) => s.identity).toSet();
        
        // Debug: Log active speakers
        if (currentSpeakers.isNotEmpty) {
          print('🎤 Active speakers: $currentSpeakers');
        }
        
        // Emit false for speakers who stopped speaking
        for (final prevSpeaker in _previousSpeakers) {
          if (!currentSpeakers.contains(prevSpeaker)) {
            print('🔇 Speaker stopped: $prevSpeaker');
            _speakingChangedController.add({
              'participantId': prevSpeaker,
              'isSpeaking': false,
            });
          }
        }
        
        // Emit true for new speakers
        for (final speaker in event.speakers) {
          if (!_previousSpeakers.contains(speaker.identity)) {
            print('🎤 Speaker started: ${speaker.identity}');
            _speakingChangedController.add({
              'participantId': speaker.identity,
              'isSpeaking': true,
            });
          }
        }
        
        // Update previous speakers set
        _previousSpeakers = currentSpeakers;
      })
      ..on<LocalTrackPublishedEvent>((event) {
        print('Local track published: ${event.publication.sid}');
      })
      ..on<TrackMutedEvent>((event) {
        print('Track muted: ${event.participant.identity}');
      })
      ..on<TrackUnmutedEvent>((event) {
        print('Track unmuted: ${event.participant.identity}');
      });
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _reconnectingController.close();
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _errorController.close();
    _audioOutputChangedController.close();
    _videoStateChangedController.close();
    _screenShareChangedController.close();
  }
}
