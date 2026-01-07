import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/main_home_content.dart';
import 'map_screen.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/user_menu_button.dart';
import 'weather_screen.dart';
import 'achievements_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkTheme;

  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final GlobalKey _keyMap = GlobalKey();
  final GlobalKey _keyAchievements = GlobalKey();
  final GlobalKey _keyWeather = GlobalKey();

  // Keep heavy screens alive
  late final List<Widget> _tabs = <Widget>[
    const MainHomeContent(),
    const MapScreen(),
    const _AchievementsGate(),
    const WeatherScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Pecazom'),
            centerTitle: false,
            actions: [
              if (user != null)
                const UserMenuButton()
              else
                IconButton(
                  tooltip: 'Bejelentkezés',
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AuthDialog(
                      onSuccess: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sikeres bejelentkezés')),
                        );
                      },
                    ),
                  ),
                ),
              IconButton(
                tooltip: widget.isDarkTheme ? 'Világos mód' : 'Sötét mód',
                icon: Icon(
                  widget.isDarkTheme
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                onPressed: widget.onToggleTheme,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: _tabs,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Főoldal',
              ),
              NavigationDestination(
                key: _keyMap,
                icon: const Icon(Icons.map_outlined),
                selectedIcon: const Icon(Icons.map),
                label: 'Térkép',
              ),
              NavigationDestination(
                key: _keyAchievements,
                icon: const Icon(Icons.emoji_events_outlined),
                selectedIcon: const Icon(Icons.emoji_events),
                label: 'Eredmények',
              ),
              NavigationDestination(
                key: _keyWeather,
                icon: const Icon(Icons.wb_sunny_outlined),
                selectedIcon: const Icon(Icons.wb_sunny),
                label: 'Időjárás',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gate the achievements tab behind auth without passing empty userId.
class _AchievementsGate extends StatelessWidget {
  const _AchievementsGate();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Az eredmények megtekintéséhez be kell jelentkezned.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => AuthDialog(
                          onSuccess: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Sikeres bejelentkezés')),
                            );
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      child: const Text('Bejelentkezés'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AchievementsScreen(userId: user.uid);
  }
}
