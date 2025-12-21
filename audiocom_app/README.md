# AudioCom Flutter App

A native Flutter voice chat client for AudioCom server.

## Features

- 🎙️ Real-time voice chat using LiveKit
- 💬 Text chat in voice channels
- 🔐 Server password authentication
- 📱 True background audio support (iOS & Android)
- 🔊 Mute/Unmute controls
- 🎧 Deafen support
- 📋 Room listing and creation

## Setup

### 1. Configure Server URL

Edit `lib/config/api_config.dart` to set your server URL:

```dart
// For Android Emulator (localhost maps to 10.0.2.2)
static const String baseUrl = 'http://10.0.2.2:3000';

// For iOS Simulator
static const String baseUrl = 'http://localhost:3000';

// For physical device (use your machine's IP)
static const String baseUrl = 'http://192.168.1.x:3000';
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the App

```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Debug mode with hot reload
flutter run
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── config/
│   └── api_config.dart       # Server configuration
├── models/
│   ├── user.dart             # User model
│   ├── room.dart             # Room model
│   └── chat_message.dart     # Chat message model
├── services/
│   ├── api_service.dart      # REST API client
│   ├── websocket_service.dart # WebSocket for events
│   └── livekit_service.dart  # LiveKit voice handling
├── providers/
│   ├── auth_provider.dart    # Authentication state
│   ├── room_provider.dart    # Room/chat state
│   └── audio_provider.dart   # Voice/audio state
└── screens/
    ├── login_screen.dart     # Login UI
    ├── rooms_screen.dart     # Room list UI
    └── voice_room_screen.dart # Voice channel UI
```

## Platform Permissions

### Android
Permissions are configured in `android/app/src/main/AndroidManifest.xml`:
- `INTERNET` - Network access
- `RECORD_AUDIO` - Microphone access
- `MODIFY_AUDIO_SETTINGS` - Audio control
- `WAKE_LOCK` - Keep device awake during calls
- `FOREGROUND_SERVICE` - Background audio

### iOS
Permissions are configured in `ios/Runner/Info.plist`:
- `NSMicrophoneUsageDescription` - Microphone access
- `UIBackgroundModes` - audio, voip, fetch for background operation

## Building for Release

### Android APK
```bash
flutter build apk --release
```

### iOS IPA
```bash
flutter build ios --release
```

## Notes

- The app connects to the same AudioCom server as the web client
- Background audio works natively without browser limitations
- Server password is required to connect (same as web client)

