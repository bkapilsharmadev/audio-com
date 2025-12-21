import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Foreground Service Handler for background audio
class ForegroundServiceHandler {
  static bool _isInitialized = false;

  /// Initialize the foreground task
  static Future<void> init() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'audiocom_voice_channel',
        channelName: 'AudioCom Voice',
        channelDescription: 'Keeps voice call active in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        showWhen: false,
        visibility: NotificationVisibility.VISIBILITY_SECRET,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
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

    // Request notification permission for Android 13+
    final notificationPermission = 
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check if already running
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      notificationTitle: '',
      notificationText: '',
      callback: startCallback,
    );
    
    return result is ServiceRequestSuccess;
  }

  /// Update the notification text
  static Future<void> updateNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'AudioCom',
        notificationText: text,
      );
    }
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
    // The actual audio is handled by LiveKit which runs in native code
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Called when the task is destroyed
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button presses
    // 'mute' or 'leave' buttons
  }

  @override
  void onNotificationPressed() {
    // When notification is tapped, bring app to foreground
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // Notification dismissed (swiped away)
    // Don't stop the service - user should explicitly leave
  }
}
