import 'package:shared_preferences/shared_preferences.dart';

/// Settings Service - manages app settings with persistence
class SettingsService {
  static const String _audioBitrateKey = 'audio_bitrate_kbps';
  static const int defaultBitrate = 32; // 32 kbps default
  
  static SettingsService? _instance;
  SharedPreferences? _prefs;
  
  SettingsService._();
  
  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }
  
  /// Get audio bitrate in kbps (0-128)
  int get audioBitrateKbps {
    return _prefs?.getInt(_audioBitrateKey) ?? defaultBitrate;
  }
  
  /// Set audio bitrate in kbps (0-128)
  Future<void> setAudioBitrateKbps(int kbps) async {
    // Clamp to valid range
    final clamped = kbps.clamp(8, 128);
    await _prefs?.setInt(_audioBitrateKey, clamped);
  }
  
  /// Get audio bitrate in bps (for LiveKit)
  int get audioBitrateBps => audioBitrateKbps * 1000;
}
