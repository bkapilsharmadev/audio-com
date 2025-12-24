import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Standard Android Foreground Service Types
class ServiceType {
  static const int MEDIA_PLAYBACK = 2;
  static const int MEDIA_PROJECTION = 32;
  static const int MICROPHONE = 128;
}

/// Foreground Service Handler for background audio
class ForegroundServiceHandler {
  static bool _isInitialized = false;
  static String? _currentRoomName;

  /// Initialize the foreground task
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ks_meet_call_channel',
        channelName: 'KS Meet Calls',
        channelDescription: 'Active voice call notification',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        playSound: false,
        enableVibration: false,
        showWhen: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Start the foreground service when joining a voice call
  static Future<bool> startService(String roomName) async {
    await init();
    _currentRoomName = roomName;

    // Request notification permission
    final notificationPermission = 
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await updateNotification('In call: $roomName');
      return true;
    }

    try {
      // Default: Microphone + Media Playback
      // Service types are read from Manifest in v9
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'KS Meet',
        notificationText: 'In call: $roomName',
        callback: startCallback,
      );
      
      return result is ServiceRequestSuccess;
    } catch (e) {
      print('⚠️ Foreground service failed to start: $e');
      return false;
    }
  }

  /// Restart service with screen sharing capability
  static Future<bool> setScreenShareEnabled(bool enabled) async {
    if (!await FlutterForegroundTask.isRunningService) return false;
    
    final roomName = _currentRoomName ?? 'Voice Call';
    
    // Stop current service
    await FlutterForegroundTask.stopService();
    
    // Restart service
    // Note: Types are driven by Manifest. This restart is mainly to 
    // refresh the notification or state if needed.
    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'KS Meet',
        notificationText: 'In call: $roomName',
        callback: startCallback,
      );
      return result is ServiceRequestSuccess;
    } catch(e) {
       print('Error restarting service for screen share: $e');
       return false;
    }
  }

  /// Update the notification text
  static Future<void> updateNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'KS Meet',
        notificationText: text,
      );
    }
  }

  /// Update notification with mute status
  static Future<void> updateMuteStatus(bool isMuted, {String? roomName}) async {
    final room = roomName ?? _currentRoomName ?? 'Voice Call';
    final muteText = isMuted ? '🔇 Muted' : '🎤 Unmuted';
    await updateNotification('$room • $muteText');
  }

  /// Stop the foreground service when leaving voice call
  static Future<bool> stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.stopService();
      return result is ServiceRequestSuccess;
    }
    return true;
  }

  /// Check if service is running
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

/// Callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioTaskHandler());
}

/// Task handler that runs in the background
class AudioTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Called when the task is started
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This keeps the service alive
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Called when the task is destroyed
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button presses
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // Notification dismissed
  }
}
