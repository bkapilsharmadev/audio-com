# AudioCom - Voice Communication Platform

> A real-time voice communication platform with Flutter mobile app and Node.js backend using LiveKit SFU.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Technology Stack](#technology-stack)
3. [Project Structure](#project-structure)
4. [Server Components](#server-components)
5. [Flutter Client Components](#flutter-client-components)
6. [WebSocket Protocol](#websocket-protocol)
7. [Data Models](#data-models)
8. [Connection Flows](#connection-flows)
9. [Network Status Handling](#network-status-handling)
10. [Voice Channel Flow](#voice-channel-flow)
11. [Auto-Rejoin Feature](#auto-rejoin-feature)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AUDIOCOM ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────┐          ┌──────────────┐          ┌──────────────┐     │
│   │   Flutter    │          │   Node.js    │          │   LiveKit    │     │
│   │   Mobile     │◄────────►│   Server     │◄────────►│   SFU        │     │
│   │   App        │   WS     │  (Express)   │  Proxy   │   Server     │     │
│   └──────────────┘          └──────────────┘          └──────────────┘     │
│         │                         │                         │              │
│         │                         │                         │              │
│         │     REST API            │     Session             │              │
│         │◄────────────────────────│     Persistence         │              │
│         │                         │                         │              │
│         │                    ┌────▼────┐                    │              │
│         │                    │sessions │                    │              │
│         │ LiveKit SDK        │  .json  │         Audio/     │              │
│         │◄──────────────────►│         │◄────────Video──────│              │
│         │                    └─────────┘                    │              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Role | Technology |
|-----------|------|------------|
| **Flutter App** | Mobile client for voice communication | Dart, Flutter, LiveKit SDK |
| **Node.js Server** | REST API, WebSocket, Session management | Node.js, Express, ws |
| **LiveKit SFU** | Selective Forwarding Unit for voice streams | LiveKit Server |
| **Session Store** | File-based persistence for user sessions | JSON file |

---

## Technology Stack

### Server
- **Runtime**: Node.js
- **Framework**: Express.js
- **WebSocket**: `ws` library
- **LiveKit**: `livekit-server-sdk` for token generation
- **Persistence**: JSON file-based session store

### Flutter Client
- **Framework**: Flutter 3.x
- **State Management**: Provider
- **Voice SDK**: `livekit_client`
- **HTTP**: `http` package
- **WebSocket**: `web_socket_channel`
- **Background**: `flutter_foreground_task`, `wakelock_plus`

---

## Project Structure

```
audio-com/
├── 📁 server (Node.js Backend)
│   ├── server.js                    # Main server entry point
│   ├── sessionStore.js              # File-based session persistence
│   ├── package.json                 # Node.js dependencies
│   ├── livekit.conf                 # LiveKit server configuration
│   └── 📁 data/
│       └── sessions.json            # Persisted sessions
│
├── 📁 audiocom_app (Flutter Client)
│   └── 📁 lib/
│       ├── main.dart                # App entry point
│       ├── 📁 config/
│       │   └── api_config.dart      # Server URL configuration
│       ├── 📁 models/
│       │   ├── user.dart            # User data model
│       │   ├── room.dart            # Room data model
│       │   └── chat_message.dart    # Chat message model
│       ├── 📁 providers/
│       │   ├── auth_provider.dart   # Authentication state
│       │   ├── room_provider.dart   # Room & users state
│       │   └── audio_provider.dart  # Voice/audio state
│       ├── 📁 services/
│       │   ├── api_service.dart     # REST API calls
│       │   ├── websocket_service.dart# WebSocket connection
│       │   ├── livekit_service.dart # LiveKit voice handling
│       │   ├── settings_service.dart# User preferences
│       │   └── foreground_service.dart# Background audio
│       └── 📁 screens/
│           ├── login_screen.dart    # Login UI
│           ├── rooms_screen.dart    # Room list UI
│           ├── voice_room_screen.dart# Voice channel UI
│           └── settings_screen.dart # Settings UI
│
└── 📁 public (Web Client - Legacy)
    ├── index.html
    └── 📁 js/
        ├── app.js
        ├── mumble-client.js
        ├── audio-handler.js
        └── livekit-client.js
```

---

## Server Components

### `server.js` - Main Server

| Section | Lines | Purpose |
|---------|-------|---------|
| **Server Setup** | 1-70 | HTTPS/HTTP initialization |
| **WebSocket Setup** | 78-432 | WS connection handling, message routing |
| **LiveKit Proxy** | 573-589 | Proxy LiveKit through server for HTTPS |
| **REST API - Rooms** | 674-815 | Room CRUD operations |
| **REST API - Users** | 816-1040 | User registration, state management |
| **Graceful Shutdown** | 68-76 | Clean server shutdown |

#### Key In-Memory Data Structures

```javascript
const rooms = new Map();   // Room ID → Room object
const users = new Map();   // User ID → User object
const invites = new Map(); // Invite code → Room ID
```

### `sessionStore.js` - Session Persistence

| Method | Purpose |
|--------|---------|
| `save(session)` | Save/update user session |
| `remove(userId)` | Delete user session |
| `get(userId)` | Retrieve session by ID |
| `getAll()` | Get all sessions |
| `touch(userId)` | Update lastSeen timestamp |
| `cleanup(expiryMs, activeIds)` | Remove stale sessions |
| `isUsernameTaken(name, excludeId)` | Check username availability |

---

## Flutter Client Components

### Providers (State Management)

#### `auth_provider.dart`
| Property/Method | Purpose |
|-----------------|---------|
| `currentUser` | Currently logged in user |
| `isLoggedIn` | Authentication status |
| `register(name, password)` | Register/login user |
| `logout()` | Logout and clear session |
| `_connectWebSocket()` | Establish WebSocket connection |

#### `room_provider.dart`
| Property/Method | Purpose |
|-----------------|---------|
| `rooms` | List of available rooms |
| `currentRoom` | Currently joined room |
| `roomUsers` | Users in current room |
| `chatMessages` | Room chat messages |
| `fetchRooms()` | Load room list from API |
| `joinRoom(userId, roomId)` | Join a room |
| `leaveRoom()` | Leave current room |
| `sendChatMessage(content)` | Send chat message |

#### `audio_provider.dart`
| Property/Method | Purpose |
|-----------------|---------|
| `isInVoiceChannel` | Voice connection status |
| `isMuted` | Microphone mute state |
| `isDeafened` | Audio output mute state |
| `isReconnecting` | Reconnection in progress |
| `joinVoice(roomId, userId, userName)` | Join voice channel |
| `leaveVoice()` | Leave voice channel |
| `toggleMute()` | Toggle microphone |
| `toggleDeafen()` | Toggle audio output |
| `_attemptVoiceRejoin()` | Auto-rejoin after network recovery |

### Services

#### `websocket_service.dart`
Handles real-time WebSocket communication with automatic reconnection.

| Feature | Implementation |
|---------|----------------|
| **Auto-Reconnect** | Exponential backoff (2s, 4s, 8s... max 30s) |
| **Max Attempts** | 10 attempts before giving up |
| **Intentional vs Network** | Tracks `_intentionalDisconnect` flag |
| **Heartbeat** | Every 25 seconds |

#### `livekit_service.dart`
Manages LiveKit voice connection and audio streams.

| Feature | Implementation |
|---------|----------------|
| **Voice Activity Detection** | `ActiveSpeakersChangedEvent` |
| **Reconnection** | Built-in LiveKit reconnection handling |
| **Deafen** | Disables all remote audio track publications |
| **Mute** | Disables local microphone track |

---

## WebSocket Protocol

### Message Flow

```
Client                          Server                         Other Clients
  │                               │                                │
  │  WS Connect                   │                                │
  │──────────────────────────────►│                                │
  │                               │                                │
  │  { type: 'register',          │                                │
  │    userId: 'xxx' }            │                                │
  │──────────────────────────────►│                                │
  │                               │  Store WS ↔ userId mapping     │
  │                               │                                │
  │  { type: 'join-room',         │                                │
  │    roomId: 'lobby' }          │                                │
  │──────────────────────────────►│                                │
  │                               │  { type: 'user-joined',        │
  │                               │    userId, userName }          │
  │                               │───────────────────────────────►│
```

### Client → Server Messages

| Type | Payload | Purpose |
|------|---------|---------|
| `register` | `{ userId }` | Associate WS with user |
| `join-room` | `{ roomId }` | Notify room join |
| `leave-room` | `{ roomId }` | **Intentional** leave (removes from room) |
| `speaking` | `{ isSpeaking: bool }` | Voice activity |
| `network-status` | `{ networkStatus }` | Client-reported status |
| `chat-message` | `{ content }` | Send chat |
| `heartbeat` | `{ timestamp }` | Keep-alive |
| `invalidate-user` | `{ userId }` | Force logout old session |

### Server → Client Messages

| Type | Payload | Trigger |
|------|---------|---------|
| `user-joined` | `{ userId, userName }` | User joined room |
| `user-left` | `{ userId, userName }` | User left room |
| `user-speaking` | `{ userId, isSpeaking }` | Speaking state changed |
| `user-network-status` | `{ userId, userName, networkStatus }` | Connection quality |
| `chat-message` | `{ userId, userName, content, timestamp }` | New message |
| `heartbeat-ack` | `{ timestamp, serverTime }` | Heartbeat response |

---

## Data Models

### User (Server - In Memory)

```javascript
{
  id: "uuid-v4",
  name: "JohnDoe",
  roomId: "lobby" | null,
  isMuted: false,
  isDeafened: false,
  isSpeaking: false,
  networkStatus: "good" | "weak" | "disconnected" | "reconnecting" | "left",
  connectedAt: Date,
  lastSeen: timestamp
}
```

### User (Flutter - `user.dart`)

```dart
class User {
  final String id;
  final String name;
  String? roomId;
  bool isMuted;
  bool isDeafened;
  bool isSpeaking;
  String networkStatus;  // 'good', 'weak', 'disconnected', 'reconnecting'
  final DateTime? connectedAt;
  final String? token;
}
```

### Room (Server)

```javascript
{
  id: "lobby",
  name: "Lobby",
  description: "Main lobby",
  isPrivate: false,
  isPasswordProtected: false,
  password: "hashed" | null,
  maxUsers: 100,
  users: Set<userId>,
  createdAt: Date
}
```

### Session (Persisted - `sessions.json`)

```json
{
  "user-uuid": {
    "userId": "uuid-v4",
    "username": "JohnDoe",
    "roomId": "lobby",
    "lastSeen": 1703187600000
  }
}
```

---

## Connection Flows

### 1. User Registration & Login

```
┌─────────────┐    POST /api/users/register    ┌─────────────┐
│   Flutter   │───────────────────────────────►│   Server    │
│   Client    │   { name, serverPassword,      │             │
│             │     userId? }                  │             │
│             │                                │             │
│             │◄───────────────────────────────│  Create/    │
│             │   { id, name, token,           │  Restore    │
│             │     roomId?, reconnected? }    │  User       │
└─────────────┘                                └─────────────┘
       │
       │  WebSocket Connect
       ▼
┌─────────────┐    { type: 'register' }        ┌─────────────┐
│   Flutter   │───────────────────────────────►│   Server    │
│   Client    │                                │   WS        │
│             │                                │             │
│             │  Store ws.userId mapping       │             │
│             │  Close old sockets for userId  │             │
└─────────────┘                                └─────────────┘
```

### 2. Joining a Room

```
┌─────────────┐  POST /api/users/:id/join/:roomId  ┌─────────────┐
│   Flutter   │───────────────────────────────────►│   Server    │
│   Client    │   { password? }                    │             │
│             │                                    │  - Validate │
│             │◄───────────────────────────────────│  - Add to   │
│             │   { success, roomName }            │    room.users│
└─────────────┘                                    └─────────────┘
       │
       │  WS: { type: 'join-room' }
       ▼
┌─────────────┐                                ┌─────────────┐
│   Server    │    { type: 'user-joined' }     │   Other     │
│   WS        │───────────────────────────────►│   Clients   │
│             │                                │             │
└─────────────┘                                └─────────────┘
       │
       │  POST /api/livekit/token
       ▼
┌─────────────┐    LiveKit Connect             ┌─────────────┐
│   Flutter   │───────────────────────────────►│   LiveKit   │
│   LiveKit   │                                │   SFU       │
│   Client    │◄───────────────────────────────│             │
│             │    Audio Stream                │             │
└─────────────┘                                └─────────────┘
```

### 3. Leaving a Room (Intentional)

```
┌─────────────┐    WS: { type: 'leave-room' }  ┌─────────────┐
│   Flutter   │───────────────────────────────►│   Server    │
│   Client    │                                │             │
│             │                                │  - Remove   │
│             │                                │    from room│
│             │                                │  - Set room │
│             │                                │    Id = null│
└─────────────┘                                └─────────────┘
                                                      │
       ┌──────────────────────────────────────────────┘
       ▼
┌─────────────┐    { type: 'user-left' }       ┌─────────────┐
│   Server    │───────────────────────────────►│   Other     │
│   WS        │                                │   Clients   │
└─────────────┘                                └─────────────┘
```

---

## Network Status Handling

### Status Values

| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| `good` | None | Green | Connected normally |
| `weak` | 📶 (2 bars) | Orange | 1-3 missed server pings |
| `reconnecting` | 📵 (wifi off) | Red | WS closed, attempting reconnect |
| `disconnected` | 📵 (signal off) | Red | 4+ missed pings or max reconnect attempts |
| `left` | — | — | User intentionally left |

### State Machine

```
                    ┌───────────────────────────────────────┐
                    │                                       │
                    ▼                                       │
┌──────────┐    WS Open     ┌──────────┐   WS Close     ┌───┴─────────┐
│          │───────────────►│          │ (no leave-room)│             │
│   N/A    │                │   GOOD   │───────────────►│ RECONNECTING│
│          │                │          │                │             │
└──────────┘                └────┬─────┘                └──────┬──────┘
                                 │                              │
                         Missed  │                              │
                         1-3     │                              │ WS Reconnects
                         pings   │                              │ + Register
                                 ▼                              │
                            ┌──────────┐                        │
                            │   WEAK   │                        │
                            │          │                        │
                            └────┬─────┘                        │
                                 │                              │
                         4+ missed                              │
                         pings   │                              │
                                 ▼                              │
                            ┌──────────┐                   ┌────▼─────┐
                            │DISCONN-  │                   │          │
                            │ ECTED    │                   │   GOOD   │
                            │          │                   │          │
                            └──────────┘                   └──────────┘
```

---

## Voice Channel Flow

### LiveKit Integration

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         VOICE CHANNEL FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Flutter App            Node.js Server              LiveKit SFU        │
│       │                       │                          │              │
│       │  POST /livekit/token  │                          │              │
│       │──────────────────────►│                          │              │
│       │                       │                          │              │
│       │◄──────────────────────│  Generate JWT            │              │
│       │  { token, url }       │  with permissions        │              │
│       │                       │                          │              │
│       │                       │                          │              │
│       │  room.connect(url, token)                        │              │
│       │─────────────────────────────────────────────────►│              │
│       │                       │                          │              │
│       │  setMicrophoneEnabled(true)                      │              │
│       │─────────────────────────────────────────────────►│              │
│       │                       │                          │              │
│       │◄─────────────────────────────────────────────────│              │
│       │  Audio streams from other participants          │              │
│       │                       │                          │              │
│       │  ActiveSpeakersChanged │                         │              │
│       │◄─────────────────────────────────────────────────│              │
│       │                       │                          │              │
│       │  WS: speaking state   │                          │              │
│       │──────────────────────►│  Broadcast to room       │              │
│       │                       │                          │              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Mute/Deafen Handling

| Action | LocalParticipant | RemoteParticipants | Server Notification |
|--------|------------------|--------------------|--------------------|
| **Mute** | `setMicrophoneEnabled(false)` | — | `updateUserState(isMuted: true)` |
| **Unmute** | `setMicrophoneEnabled(true)` | — | `updateUserState(isMuted: false)` |
| **Deafen** | Also mutes if unmuted | `publication.disable()` for all | `updateUserState(isDeafened: true)` |
| **Undeafen** | — | `publication.enable()` for all | `updateUserState(isDeafened: false)` |

---

## Auto-Rejoin Feature

### Purpose
Automatically reconnect to voice channel after network recovery without user intervention.

### Implementation

```dart
// audio_provider.dart

// On network disconnect (not intentional leave):
if (_lastRoomId != null && _lastUserId != null) {
  _pendingVoiceRejoin = true;  // Mark for auto-rejoin
}

// When WebSocket reconnects:
_wsConnectionSub = _wsService.onConnectionStateChanged.listen((isWsConnected) {
  if (isWsConnected && _pendingVoiceRejoin) {
    _attemptVoiceRejoin();  // Auto-rejoin voice
  }
});
```

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       AUTO-REJOIN FLOW                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   NETWORK DROPS                                                         │
│        │                                                                │
│        ▼                                                                │
│   LiveKit disconnects                                                   │
│        │                                                                │
│        ├──► Store _lastRoomId, _lastUserId, _lastUserName               │
│        │                                                                │
│        ├──► Set _pendingVoiceRejoin = true                              │
│        │                                                                │
│        └──► WebSocket auto-reconnects (with exponential backoff)        │
│                                                                         │
│   NETWORK RECOVERS                                                      │
│        │                                                                │
│        ▼                                                                │
│   WebSocket connects                                                    │
│        │                                                                │
│        ├──► Sends 'register' message                                    │
│        │                                                                │
│        ├──► Server broadcasts 'good' network status                     │
│        │                                                                │
│        └──► _wsConnectionSub triggers _attemptVoiceRejoin()             │
│                  │                                                      │
│                  ├──► Wait 1 second (network stability)                 │
│                  │                                                      │
│                  ├──► joinVoice(_lastRoomId, _lastUserId, ...)          │
│                  │                                                      │
│                  └──► ✓ User back in voice channel!                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Behaviors

| Scenario | Auto-Rejoin? | Reason |
|----------|--------------|--------|
| User presses Leave/Back | ❌ No | `_last*` info cleared |
| Network drops temporarily | ✅ Yes | `_pendingVoiceRejoin = true` |
| App killed and restarted | ❌ No | In-memory state lost |
| Server restarts | ✅ Yes (room) | Session persisted in `sessions.json` |

---

## API Endpoints

### Authentication
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/users/register` | Register or reconnect user |

### Rooms
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/rooms` | List all public rooms |
| GET | `/api/rooms/:id` | Get room details |
| POST | `/api/rooms` | Create a new room |
| DELETE | `/api/rooms/:id` | Delete a room |
| GET | `/api/rooms/:id/requires-password` | Check if room needs password |

### Users
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/users` | List users (optionally by room) |
| GET | `/api/users/:id` | Get specific user |
| POST | `/api/users/:userId/join/:roomId` | Join a room |
| PUT | `/api/users/:id/state` | Update mute/deafen state |

### LiveKit
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/livekit/token` | Generate LiveKit access token |

### System
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/health` | Health check |
| GET | `/api/server/info` | Server information |

---

## Environment Variables

```env
# Server
PORT=3000
HOST=0.0.0.0
HTTPS=false
SERVER_PASSWORD=your_password

# LiveKit
LIVEKIT_URL=ws://localhost:7880
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret
LIVEKIT_INTERNAL_URL=http://127.0.0.1:7880

# Session
SESSION_DIR=./data
```

---

## Running the Project

### Server
```bash
cd audio-com
npm install
node server.js
```

### LiveKit (Docker)
```bash
docker-compose up -d
```

### Flutter App
```bash
cd audiocom_app
flutter pub get
flutter run
```

---

## Key Files Reference

| Category | File | Purpose |
|----------|------|---------|
| **Server Entry** | `server.js` | Main Node.js server |
| **Session Storage** | `sessionStore.js` | File-based persistence |
| **Flutter Entry** | `lib/main.dart` | App initialization |
| **Auth State** | `lib/providers/auth_provider.dart` | Login/logout |
| **Room State** | `lib/providers/room_provider.dart` | Room management |
| **Audio State** | `lib/providers/audio_provider.dart` | Voice control |
| **WebSocket** | `lib/services/websocket_service.dart` | Real-time messaging |
| **LiveKit** | `lib/services/livekit_service.dart` | Voice streaming |
| **Voice UI** | `lib/screens/voice_room_screen.dart` | Voice room interface |

---

*Last updated: December 21, 2025*
