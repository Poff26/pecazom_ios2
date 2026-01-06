import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

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

  // Hasznos, ha iOS-en “csak kilép” – legalább logolunk mindent, amit lehet.
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

  // Firebase init
  try {
    debugPrint('MAIN: before Firebase.initializeApp');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('MAIN: after Firebase.initializeApp');
  } catch (e, st) {
    debugPrint('MAIN: Firebase init ERROR: $e');
    debugPrint('$st');
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Theme pref
  bool isDarkMode = false;
  try {
    debugPrint('MAIN: before SharedPreferences.getInstance');
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 4));
    isDarkMode = prefs.getBool('darkMode') ?? false;
    debugPrint('MAIN: after SharedPreferences.getInstance (dark=$isDarkMode)');
  } catch (e, st) {
    debugPrint('MAIN: SharedPreferences WARNING: $e');
    debugPrint('$st');
  }

  // Local notifications init (Android + iOS)
  try {
    debugPrint('MAIN: before _initLocalNotifications');
    await _initLocalNotifications().timeout(const Duration(seconds: 8));
    debugPrint('MAIN: after _initLocalNotifications');
  } catch (e, st) {
    debugPrint('MAIN: LocalNotifications WARNING: $e');
    debugPrint('$st');
  }

  runApp(FishingApp(initialDarkMode: isDarkMode));
  debugPrint('MAIN: after runApp');
}

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const darwinInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
  );

  await _localNotif.initialize(initSettings);

  final androidPlugin =
      _localNotif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
    _initPushNotifications();
  }

  Future<void> _initPushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission();

      FirebaseMessaging.onMessage.listen((msg) {
        final notif = msg.notification;
        // iOS-en ne próbáljunk Android local notificationt küldeni
        if (notif == null || !Platform.isAndroid) return;

        _localNotif.show(
          notif.hashCode,
          notif.title,
          notif.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        final route = msg.data['route'];
        if (route is String) {
          navigatorKey.currentState?.pushNamed(route);
        }
      });
    } catch (e, st) {
      debugPrint('PUSH INIT WARNING: $e');
      debugPrint('$st');
    }
  }

  Future<void> toggleTheme() async {
    setState(() => isDarkTheme = !isDarkTheme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDarkTheme);
  }

  ThemeData _buildLightTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.lightBlue);
    return ThemeData(useMaterial3: true, colorScheme: scheme);
  }

  ThemeData _buildDarkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.lightBlue,
      brightness: Brightness.dark,
    );
    return ThemeData(useMaterial3: true, colorScheme: scheme);
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        // Loader nélkül: közvetlenül HomeScreen
        return MaterialPageRoute(
          builder: (_) => HomeScreen(
            isDarkTheme: isDarkTheme,
            onToggleTheme: toggleTheme,
          ),
        );

      case '/subscription':
        return MaterialPageRoute(
          builder: (_) => const SubscriptionScreen(),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Ismeretlen oldal')),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Pecazom',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
