import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_update/in_app_update.dart';

import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Fontos értesítések',
  description: 'Minden fontos Pecazom értesítés',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    debugPrint('${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('$stack');
    return true;
  };

  debugPrint('MAIN: start');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  // Ads csak Androidon
  if (Platform.isAndroid) {
    try {
      await MobileAds.instance
          .initialize()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  bool isDarkMode = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('darkMode') ?? false;
  } catch (_) {}

  await _initLocalNotifications();

  runApp(FishingApp(initialDarkMode: isDarkMode));
}

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinInit = DarwinInitializationSettings();

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
  );

  await _localNotif.initialize(initSettings);

  final androidPlugin =
      _localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_channel);
}

class FishingApp extends StatefulWidget {
  final bool initialDarkMode;
  const FishingApp({super.key, required this.initialDarkMode});

  @override
  State<FishingApp> createState() => _FishingAppState();
}

class _FishingAppState extends State<FishingApp> {
  late bool isDarkTheme;

  @override
  void initState() {
    super.initState();
    isDarkTheme = widget.initialDarkMode;
    _initPush();
  }

  Future<void> _initPush() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    setState(() => isDarkTheme = !isDarkTheme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDarkTheme);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Pecazom',
      themeMode: isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true),
      darkTheme:
          ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: BootLoader(
        isDarkTheme: isDarkTheme,
        onToggleTheme: toggleTheme,
      ),
      routes: {
        '/subscription': (_) => const SubscriptionScreen(),
      },
    );
  }
}

/* ============================================================
   SAFE BOOT LOADER (NO VIDEO, NO ASSETS)
   ============================================================ */

class BootLoader extends StatefulWidget {
  final bool isDarkTheme;
  final Future<void> Function() onToggleTheme;

  const BootLoader({
    super.key,
    required this.isDarkTheme,
    required this.onToggleTheme,
  });

  @override
  State<BootLoader> createState() => _BootLoaderState();
}

class _BootLoaderState extends State<BootLoader> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return HomeScreen(
      isDarkTheme: widget.isDarkTheme,
      onToggleTheme: widget.onToggleTheme,
    );
  }
}
