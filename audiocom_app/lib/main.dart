import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/audio_provider.dart';
import 'screens/login_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/voice_room_screen.dart';
import 'screens/settings_screen.dart';
import 'services/foreground_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize foreground service handler
  ForegroundServiceHandler.init();
  runApp(const AudioComApp());
}

class AudioComApp extends StatefulWidget {
  const AudioComApp({super.key});

  @override
  State<AudioComApp> createState() => _AudioComAppState();
}

class _AudioComAppState extends State<AudioComApp> with WidgetsBindingObserver {
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cleanup on app dispose
    _authProvider?.logout();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app is detached (terminated), logout to cleanup server-side
    if (state == AppLifecycleState.detached) {
      _authProvider?.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Provider (owns WebSocketService)
        ChangeNotifierProvider(create: (_) {
          _authProvider = AuthProvider();
          return _authProvider!;
        }),
        
        // Room Provider (depends on WebSocketService from AuthProvider)
        ChangeNotifierProxyProvider<AuthProvider, RoomProvider>(
          create: (context) => RoomProvider(
            wsService: context.read<AuthProvider>().wsService,
          ),
          update: (context, auth, previous) => previous ?? RoomProvider(
            wsService: auth.wsService,
          ),
        ),
        
        // Audio Provider (depends on WebSocketService from AuthProvider)
        ChangeNotifierProxyProvider<AuthProvider, AudioProvider>(
          create: (context) => AudioProvider(
            wsService: context.read<AuthProvider>().wsService,
          ),
          update: (context, auth, previous) => previous ?? AudioProvider(
            wsService: auth.wsService,
          ),
        ),
      ],
      child: WithForegroundTask(
        child: MaterialApp(
          title: 'Google',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const AppInitializer(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/rooms': (context) => const RoomsScreen(),
            '/voice': (context) => const VoiceRoomScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        ),
      ),
    );
  }
}

/// App Initializer - handles initial auth check and routing
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final auth = context.read<AuthProvider>();
    final audio = context.read<AudioProvider>();
    
    await auth.initialize();
    
    // Listen for session expiration - navigate to login when triggered
    audio.onSessionExpired.listen((_) {
      if (mounted) {
        auth.handleSessionExpired();
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
    
    if (mounted) {
      if (auth.isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/rooms');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_android,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Google',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
