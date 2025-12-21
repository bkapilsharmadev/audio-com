import 'dart:async';
import 'package:livekit_client/livekit_client.dart';

/// LiveKit Service for audio communication
class LivekitService {
  Room? _room;
  LocalParticipant? _localParticipant;
  EventsListener<RoomEvent>? _roomListener;
  
  bool _isMicEnabled = false;
  bool _isConnected = false;

  // Event streams
  final _connectionStateController = StreamController<bool>.broadcast();
  final _participantJoinedController = StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController = StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController = StreamController<Map<String, dynamic>>.broadcast();
  final _trackSubscribedController = StreamController<RemoteTrackPublication>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Public streams
  Stream<bool> get onConnectionStateChanged => _connectionStateController.stream;
  Stream<RemoteParticipant> get onParticipantJoined => _participantJoinedController.stream;
  Stream<RemoteParticipant> get onParticipantLeft => _participantLeftController.stream;
  Stream<Map<String, dynamic>> get onSpeakingChanged => _speakingChangedController.stream;
  Stream<RemoteTrackPublication> get onTrackSubscribed => _trackSubscribedController.stream;
  Stream<String> get onError => _errorController.stream;

  // Getters
  bool get isConnected => _isConnected;
  bool get isMicEnabled => _isMicEnabled;
  Room? get room => _room;
  LocalParticipant? get localParticipant => _localParticipant;
  
  List<RemoteParticipant> get remoteParticipants {
    return _room?.remoteParticipants.values.toList() ?? [];
  }

  /// Connect to LiveKit room
  Future<void> connect(String url, String token) async {
    try {
      // Create room with audio-only options
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true,  // Discontinuous transmission for bandwidth saving
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
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

      print('✓ Connected to LiveKit room');
    } catch (e) {
      print('✗ Failed to connect to LiveKit: $e');
      _errorController.add('Failed to connect: $e');
      rethrow;
    }
  }

  /// Enable/disable microphone
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_localParticipant == null) return;

    try {
      await _localParticipant!.setMicrophoneEnabled(enabled);
      _isMicEnabled = enabled;
      print('Microphone ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      print('Failed to ${enabled ? "enable" : "disable"} microphone: $e');
      _errorController.add('Microphone error: $e');
    }
  }

  /// Toggle microphone
  Future<void> toggleMicrophone() async {
    await setMicrophoneEnabled(!_isMicEnabled);
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

  /// Disconnect from room
  Future<void> disconnect() async {
    _isMicEnabled = false;
    _isConnected = false;
    _isDeafened = false;  // Reset deafen state so new room starts fresh
    
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
        for (final speaker in event.speakers) {
          _speakingChangedController.add({
            'participantId': speaker.identity,
            'isSpeaking': true,
          });
        }
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
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _errorController.close();
  }
}
