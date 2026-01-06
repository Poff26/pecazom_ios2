import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:video_player/video_player.dart';

import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

/// Android-only notification channel
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
  debugPrint('MAIN: start');

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

  // Mobile Ads: iOS-en is ok, de ne blokkoljon.
  try {
    debugPrint('MAIN: before MobileAds.initialize');
    await MobileAds.instance.initialize().timeout(const Duration(seconds: 6));
    debugPrint('MAIN: after MobileAds.initialize');
  } catch (e, st) {
    debugPrint('MAIN: MobileAds init WARNING: $e');
    debugPrint('$st');
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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

  try {
    debugPrint('MAIN: before _initLocalNotifications');
    await _initLocalNotifications().timeout(const Duration(seconds: 6));
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

  // iOS init + permission prompt configuration
  const darwinInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
  );

  await _localNotif.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse resp) {
      // Ha később szeretnél route-ot kezelni local notifből:
      final payload = resp.payload;
      if (payload != null && payload.isNotEmpty) {
        navigatorKey.currentState?.pushNamed(payload);
      }
    },
  );

  // Android channel létrehozás csak Androidon
  if (Platform.isAndroid) {
    final androidPlugin =
        _localNotif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
  }
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

      // iOS: explicit permission szükséges
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // iOS: foreground notif viselkedés (különösen ha nem akarsz local notifet)
      // Itt mi local notifet is megjelenítünk, de ez segít a rendszeroldali kezelésben is.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // iOS: hasznos debughoz (APNs token)
      if (Platform.isIOS) {
        final apnsToken = await messaging.getAPNSToken();
        debugPrint('PUSH: APNs token = $apnsToken');
      }

      FirebaseMessaging.onMessage.listen((msg) async {
        final notif = msg.notification;
        if (notif == null) return;

        // Foreground: mutassunk local notifet Androidon és iOS-en is.
        await _showLocalFromRemote(notif: notif, data: msg.data);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        final route = msg.data['route'];
        if (route is String && route.isNotEmpty) {
          navigatorKey.currentState?.pushNamed(route);
        }
      });

      // Hidegindítás (app megnyitva értesítésből)
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final route = initialMessage.data['route'];
        if (route is String && route.isNotEmpty) {
          // Célszerű egy microtask, hogy Navigator biztosan készen legyen.
          scheduleMicrotask(() => navigatorKey.currentState?.pushNamed(route));
        }
      }
    } catch (e, st) {
      debugPrint('PUSH INIT WARNING: $e');
      debugPrint('$st');
    }
  }

  Future<void> _showLocalFromRemote({
    required RemoteNotification notif,
    required Map<String, dynamic> data,
  }) async {
    // Opcionális: route payload átadása local notif payloadban
    final route = data['route'];
    final payload = (route is String && route.isNotEmpty) ? route : null;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotif.show(
      notif.hashCode,
      notif.title,
      notif.body,
      details,
      payload: payload,
    );
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
        return MaterialPageRoute(
          builder: (_) => BootLoader(
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

/* ============================================================
   BOOT LOADER + LOADING VIDEO + “SAFE” PLAY UPDATE CHECK
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

class _BootLoaderState extends State<BootLoader> with WidgetsBindingObserver {
  bool _ready = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkImmediateUpdateIfNeeded();
    }
  }

  Future<void> _boot() async {
    unawaited(_checkImmediateUpdateIfNeeded());
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _checkImmediateUpdateIfNeeded() async {
    // In-app update csak Android (Play Core). iOS-en App Store.
    if (!Platform.isAndroid) return;
    if (_checkingUpdate) return;
    _checkingUpdate = true;

    if (kDebugMode) {
      debugPrint('UPDATE: skipped in debug mode');
      _checkingUpdate = false;
      return;
    }

    try {
      debugPrint('UPDATE: checkForUpdate() start');
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 6));

      debugPrint(
        'UPDATE: availability=${info.updateAvailability}, '
        'immediateAllowed=${info.immediateUpdateAllowed}, '
        'flexibleAllowed=${info.flexibleUpdateAllowed}',
      );

      final available = info.updateAvailability == UpdateAvailability.updateAvailable;
      final allowed = info.immediateUpdateAllowed;

      if (available && allowed) {
        debugPrint('UPDATE: performImmediateUpdate() start');
        await InAppUpdate.performImmediateUpdate().timeout(const Duration(seconds: 30));
        debugPrint('UPDATE: performImmediateUpdate() done');
      }
    } on TimeoutException catch (_) {
      debugPrint('UPDATE: timeout (non-blocking)');
    } catch (e, st) {
      debugPrint('UPDATE: error (non-blocking): $e');
      debugPrint('$st');
    } finally {
      _checkingUpdate = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedOpacity(
          opacity: _ready ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: const _LogoLoaderView(),
        ),
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: IgnorePointer(
            ignoring: !_ready,
            child: HomeScreen(
              isDarkTheme: widget.isDarkTheme,
              onToggleTheme: widget.onToggleTheme,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoLoaderView extends StatefulWidget {
  const _LogoLoaderView();

  @override
  State<_LogoLoaderView> createState() => _LogoLoaderViewState();
}

class _LogoLoaderViewState extends State<_LogoLoaderView> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/video/loader.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        _controller
          ..setLooping(true)
          ..play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: _controller.value.isInitialized
            ? SizedBox(
                width: 180,
                height: 180,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
