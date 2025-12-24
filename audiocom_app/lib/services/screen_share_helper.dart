import 'package:flutter/services.dart';

class ScreenShareHelper {
  static const MethodChannel _channel = MethodChannel('com.example.audiocom_app/screen_share');

  /// Start the native screen share foreground service
  static Future<void> startService() async {
    try {
      await _channel.invokeMethod('startService');
    } on PlatformException catch (e) {
      print("Failed to start screen share service: '${e.message}'.");
    }
  }

  /// Trigger permission dialog and start service if accepted
  static Future<bool> requestPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('requestPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      print("Failed to request permission: '${e.message}'.");
      return false;
    }
  }

  /// Stop the native screen share foreground service
  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print("Failed to stop screen share service: '${e.message}'.");
    }
  }
}
