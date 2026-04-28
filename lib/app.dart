import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models/person.dart';
import 'screens/auth_screen.dart';
import 'screens/circle_details_screen.dart';
import 'screens/home_dashboard.dart';
import 'services/auth_service.dart';
import 'services/global_sos_service.dart';
import 'services/session_service.dart';

class AppPreferences {
  final ThemeMode themeMode;
  final double textScale;

  const AppPreferences({
    required this.themeMode,
    required this.textScale,
  });

  AppPreferences copyWith({
    ThemeMode? themeMode,
    double? textScale,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
    );
  }
}

class AppSettingsScope
    extends InheritedNotifier<ValueNotifier<AppPreferences>> {
  const AppSettingsScope({
    super.key,
    required ValueNotifier<AppPreferences> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<AppPreferences> of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();

    if (scope == null || scope.notifier == null) {
      throw Exception('AppSettingsScope not found');
    }

    return scope.notifier!;
  }
}

class TrusTrackApp extends StatefulWidget {
  const TrusTrackApp({super.key});

  @override
  State<TrusTrackApp> createState() => _TrusTrackAppState();
}

class _TrusTrackAppState extends State<TrusTrackApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  final ValueNotifier<AppPreferences> _settings = ValueNotifier<AppPreferences>(
    const AppPreferences(
      themeMode: ThemeMode.system,
      textScale: 1.0,
    ),
  );

  final GlobalSosService _globalSosService = GlobalSosService();
  final SessionService _sessionService = SessionService();
  final AuthService _authService = AuthService();

  StreamSubscription<GlobalSosEvent>? _sosSub;
  bool _showingSosDialog = false;

  @override
  void initState() {
    super.initState();

    _globalSosService.start();

    _sosSub = _globalSosService.events.listen((event) {
      _showGlobalSosDialog(event);
    });
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _globalSosService.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _showGlobalSosDialog(GlobalSosEvent event) async {
    if (_showingSosDialog) return;

    final context = _navigatorKey.currentContext;
    if (context == null) return;

    _showingSosDialog = true;

    final goToCircle = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('SOS Alert'),
          content: Text(
            '${event.alert.senderName} sent an SOS.\n\n'
            '${event.alert.message}\n\n'
            'Circle: ${event.circleCode}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Go to circle'),
            ),
          ],
        );
      },
    );

    _showingSosDialog = false;

    if (goToCircle == true) {
      await _openSosCircle(event.circleCode);
    }
  }

  Future<void> _openSosCircle(String circleCode) async {
    final nav = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;

    if (nav == null || context == null) return;

    try {
      final Person me = await _authService.getCurrentPerson();
      final circle = await _sessionService.getSessionByCode(circleCode);

      if (circle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This circle has ended.')),
        );
        return;
      }

      nav.push(
        MaterialPageRoute(
          builder: (_) => CircleDetailsScreen(
            me: me,
            initialCircle: circle,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open circle: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B6B3A);

    return ValueListenableBuilder<AppPreferences>(
      valueListenable: _settings,
      builder: (context, prefs, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'TrusTrack',
          themeMode: prefs.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);

            return AppSettingsScope(
              notifier: _settings,
              child: MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(prefs.textScale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: green,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF4F7F5),
            appBarTheme: const AppBarTheme(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            cardTheme: CardThemeData(
              elevation: 1,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: green,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF101814),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF062E1A),
              foregroundColor: Colors.white,
            ),
            cardTheme: CardThemeData(
              elevation: 1,
              color: const Color(0xFF18241D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1F2E26),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomeDashboard();
        }

        return const AuthScreen();
      },
    );
  }
}
