import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ Banner reklám widget
import 'package:fishing_app_flutter/widgets/banner_ad_widget.dart';

import 'add_post_dialog.dart';
import 'forecast_card.dart';
import 'post_list.dart';
import 'results_stats_card.dart';

class MainHomeContent extends StatefulWidget {
  const MainHomeContent({super.key});

  @override
  State<MainHomeContent> createState() => _MainHomeContentState();
}

class _MainHomeContentState extends State<MainHomeContent>
    with TickerProviderStateMixin {
  static const String currentVersion = '2.0.2';

  String _displayName = 'Felhasználó';
  String? _activeUserId;

  TutorialCoachMark? _tutorial;
  bool _tutorialRunning = false;

  final GlobalKey _dailyHubKey = GlobalKey();
  final GlobalKey _forecastKey = GlobalKey();
  final GlobalKey _statsKey = GlobalKey();
  final GlobalKey _addPostKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();

  _DailyMetrics _metrics = const _DailyMetrics();

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _fadeCtrl,
    curve: Curves.easeOutCubic,
  );

  // XP gain overlay animation
  OverlayEntry? _xpOverlay;

  // Firestore users collection
  final _usersRef = FirebaseFirestore.instance.collection('users');

  // XP constants
  static const int _xpPerLevel = 300;
  static const int _dailyClaimXp = 15;
  static const int _xpPerPost = 10;

  // ----------------------------
  // ✅ FIX: dupla tap / race lock a napi jutalomhoz
  // ----------------------------
  bool _claimingDaily = false;

  // ----------------------------
  // STRICT forced update state (FULL SCREEN BLOCK)
  // ----------------------------
  bool _forceBlocked = false;
  String? _storeUrl;
  String? _minVersion;
  String? _latestVersion;

  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    // 1) Auth változásokat NE build-ben kezeld, hanem itt.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _onUserChanged(user);
    });

    // 2) Startup checkek első frame után (kevesebb jank)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runStartupChecks();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _fadeCtrl.dispose();
    _removeXpOverlay();
    super.dispose();
  }

  Future<void> _runStartupChecks() async {
    // Párhuzamosítva (gyorsabb indulás)
    await Future.wait([
      _checkAndShowChangelog(),
      _checkForcedUpdateStrict(),
    ]);
  }

  // ----------------------------
  // Version + forced update (STRICT)
  // Firestore doc: config/app_version
  // {
  //   force_update: true,
  //   min_version: "2.0.1",
  //   latest_version: "2.1.0",
  //   play_store_url: "https://play.google.com/store/apps/details?id=..."
  // }
  // Forced condition: force_update && currentVersion < min_version
  // ----------------------------

  Future<void> _checkForcedUpdateStrict() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_version')
          .get();
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final forceUpdate = data['force_update'] as bool? ?? false;
      final minVersion = (data['min_version'] as String?)?.trim();
      final latestVersion = (data['latest_version'] as String?)?.trim();
      final playStoreUrl = (data['play_store_url'] as String?)?.trim();

      if (!forceUpdate) {
        if (!mounted) return;
        setState(() {
          _forceBlocked = false;
          _storeUrl = playStoreUrl;
          _minVersion = minVersion;
          _latestVersion = latestVersion;
        });
        return;
      }

      if (minVersion == null || minVersion.isEmpty) return;

      final mustUpdate = _compareSemver(currentVersion, minVersion) < 0;

      if (!mounted) return;
      setState(() {
        _forceBlocked = mustUpdate;
        _storeUrl = playStoreUrl;
        _minVersion = minVersion;
        _latestVersion = latestVersion;
      });
    } catch (e) {
      debugPrint('Forced update strict check failed: $e');
    }
  }

  int _compareSemver(String a, String b) {
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first; // "2.0.0+1" -> "2.0.0"
      final parts = core.split('.');
      return [
        int.tryParse(parts.elementAtOrNull(0) ?? '0') ?? 0,
        int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0,
        int.tryParse(parts.elementAtOrNull(2) ?? '0') ?? 0,
      ];
    }

    final pa = parse(a);
    final pb = parse(b);

    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  Future<void> _openStoreStrict() async {
    final url = _storeUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A frissítési link nincs beállítva.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _checkAndShowChangelog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'changelog_shown_$currentVersion';
      final shown = prefs.getBool(key) ?? false;
      if (shown) return;

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Újdonságok – v$currentVersion'),
            content: const SingleChildScrollView(
              child: Text(
                '• Megújult főoldal és közösségi feed\n'
                '• Stabilabb bejelentkezés és értesítések\n'
                '• Teljesítmény és UX finomhangolás\n\n'
                'Visszajelzés: info@pecazom.hu',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Rendben'),
              ),
            ],
          ),
        );
      });

      await prefs.setBool(key, true);
    } catch (_) {}
  }

  // ----------------------------
  // Helpers
  // ----------------------------

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _parseDay(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s);
  }

  bool _isYesterday(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return db.difference(da).inDays == 1;
  }

  String _bestWindowString() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 6, 10);
    final end = DateTime(now.year, now.month, now.day, 8, 20);
    String fmt(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${fmt(start)}–${fmt(end)}';
  }

  int _levelFromXp(int xp) => (xp ~/ _xpPerLevel) + 1;
  double _progressFromXp(int xp) => (xp % _xpPerLevel) / _xpPerLevel;

  // ----------------------------
  // XP overlay
  // ----------------------------

  void _removeXpOverlay() {
    _xpOverlay?.remove();
    _xpOverlay = null;
  }

  void _showXpGain(int amount) {
    if (!mounted) return;

    _removeXpOverlay();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late final AnimationController ctrl;
    ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    final fade = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));

    _xpOverlay = OverlayEntry(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: SlideTransition(
                position: slide,
                child: FadeTransition(
                  opacity: fade,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.35)),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                          color: Colors.black.withOpacity(0.18),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stars_rounded, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '+$amount XP',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_xpOverlay!);

    ctrl.forward().whenComplete(() async {
      await Future.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      _removeXpOverlay();
      ctrl.dispose();
    });
  }

  // ----------------------------
  // Auth + user loading
  // ----------------------------

  Future<void> _onUserChanged(User? user) async {
    final uid = user?.uid;
    if (uid == _activeUserId) return;

    _activeUserId = uid;

    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _displayName = 'Felhasználó';
        _metrics = const _DailyMetrics();
      });
      return;
    }

    // Ezt sequential-ben hagyjuk, de csak auth váltáskor fut.
    await _loadDisplayName(uid);
    await _refreshDailyMetrics(uid);
    await _maybeStartTutorial(uid);
  }

  Future<void> _loadDisplayName(String uid) async {
    try {
      final doc = await _usersRef.doc(uid).get();
      final data = doc.data();
      final name = (data?['name'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _displayName = (name == null || name.isEmpty) ? 'Felhasználó' : name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _displayName = 'Felhasználó');
    }
  }

  Future<void> _maybeStartTutorial(String uid) async {
    if (_tutorialRunning) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'seen_main_home_tutorial_$uid';
      final seen = prefs.getBool(key) ?? false;
      if (seen) return;

      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _showTutorial(isSignedIn: true);
        await prefs.setBool(key, true);
      });
    } catch (_) {}
  }

  void _showTutorial({required bool isSignedIn}) {
    if (_tutorialRunning) return;
    _tutorialRunning = true;

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "DailyHub",
        keyTarget: _dailyHubKey,
        shape: ShapeLightFocus.RRect,
        radius: 18,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialText(
                'Ma neked: streak, napi kihívás és jutalom. Nézz rá naponta.'),
          ),
        ],
      ),
      TargetFocus(
        identify: "Forecast",
        keyTarget: _forecastKey,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialText(
                'AI előrejelzés: napi 3 lekérdezés. Ajánlott idő, csali és célhal.'),
          ),
        ],
      ),
      TargetFocus(
        identify: "Stats",
        keyTarget: _statsKey,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialText(
                'Statisztikák: a saját eredményeid és aktivitásod áttekintése.'),
          ),
        ],
      ),
      if (isSignedIn)
        TargetFocus(
          identify: "AddPost",
          keyTarget: _addPostKey,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _tutorialText('Közösség: itt tudsz új bejegyzést közzétenni.'),
            ),
          ],
        ),
      TargetFocus(
        identify: "Footer",
        keyTarget: _footerKey,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialText('Verzióinformáció és kapcsolat a képernyő alján.'),
          ),
        ],
      ),
    ];

    _tutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black.withOpacity(0.86),
      opacityShadow: 0.86,
      textSkip: 'Kihagyom',
      paddingFocus: 12,
      onFinish: () => _tutorialRunning = false,
      onSkip: () {
        _tutorialRunning = false;
        return true;
      },
    )..show(context: context);
  }

  Widget _tutorialText(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      );

  // ----------------------------
  // Firestore metrics
  // ----------------------------

  Future<void> _ensureUserDefaults(String uid) async {
    // Tranzakció helyett olcsó merge set: gyorsabb, kevesebb lock/jank.
    final today = _todayKey();
    await _usersRef.doc(uid).set(
      {
        'xp': FieldValue.increment(0),
        'level': FieldValue.increment(0),
        'streakDays': FieldValue.increment(0),
        'lastOpenDate': today,
        // ⚠️ ne töröld mindig: csak merge, ha nincs, marad null/hiányzó
        // claimedDate -> ne FieldValue.delete() defaultként (felesleges churn)
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _refreshDailyMetrics(String uid) async {
    try {
      await _ensureUserDefaults(uid);

      final today = _todayKey();
      final doc = await _usersRef.doc(uid).get();
      final data = doc.data() ?? {};

      final int xp = (data['xp'] as num?)?.toInt() ?? 0;
      final int streakDays = (data['streakDays'] as num?)?.toInt() ?? 0;

      final String? claimedDate = data['claimedDate'] as String?;
      final String? lastOpenDate = data['lastOpenDate'] as String?;

      // csak ha tényleg eltér
      if (lastOpenDate != today) {
        _usersRef.doc(uid).set({'lastOpenDate': today}, SetOptions(merge: true));
      }

      final level = _levelFromXp(xp);
      final xpProgress = _progressFromXp(xp);

      final challengeProgress = (claimedDate == today) ? 1.0 : 0.0;

      if (!mounted) return;
      setState(() {
        _metrics = _DailyMetrics(
          streakDays: streakDays,
          xp: xp,
          level: level,
          xpProgress: xpProgress,
          bestWindow: _bestWindowString(),
          challengeText: 'Vedd fel a napi jutalmat.',
          challengeProgress: challengeProgress,
          claimedToday: claimedDate == today,
          postedToday: false,
        );
      });
    } catch (_) {}
  }

  // ✅ FIX: lock + atomikus increment
  Future<void> _claimDailyReward(String uid) async {
    if (_claimingDaily) return; // ✅ dupla tap ellen
    if (!mounted) return;
    setState(() => _claimingDaily = true);

    try {
      final today = _todayKey();
      int gained = 0;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _usersRef.doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};

        final String? claimedDate = data['claimedDate'] as String?;
        if (claimedDate == today) return;

        final int streakDays = (data['streakDays'] as num?)?.toInt() ?? 0;
        final lastClaimed = _parseDay(claimedDate);
        final cur = _parseDay(today) ?? DateTime.now();

        int newStreak;
        if (lastClaimed == null) {
          newStreak = 1;
        } else if (_isYesterday(lastClaimed, cur)) {
          newStreak = (streakDays <= 0) ? 1 : (streakDays + 1);
        } else {
          newStreak = 1;
        }

        gained = _dailyClaimXp;

        // ✅ ATOMIKUS: increment + claimedDate egyszerre
        tx.set(
          ref,
          {
            'xp': FieldValue.increment(_dailyClaimXp),
            'claimedDate': today,
            'streakDays': newStreak,
            'lastOpenDate': today,
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;

      if (gained == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A mai jutalmat már felvetted.')),
        );
        return;
      }

      _showXpGain(gained);
      await _refreshDailyMetrics(uid);
    } finally {
      if (mounted) setState(() => _claimingDaily = false);
    }
  }

  Future<void> _markPostedTodayAndReward(String uid) async {
    try {
      int gained = 0;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _usersRef.doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};

        final int xp = (data['xp'] as num?)?.toInt() ?? 0;

        final int newXp = xp + _xpPerPost;
        gained = _xpPerPost;

        tx.set(
          ref,
          {
            'xp': newXp,
            'level': _levelFromXp(newXp),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      if (gained > 0) _showXpGain(gained);

      await _refreshDailyMetrics(uid);
    } catch (_) {}
  }

  // ----------------------------
  // XP info sheet
  // ----------------------------

  void _showXpInfoSheet() {
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (ctx) {
        Widget ruleRow(String title, String subtitle, IconData icon) {
          final t = Theme.of(ctx).textTheme;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: scheme.surfaceContainerHighest.withOpacity(0.55),
              border:
                  Border.all(color: scheme.outlineVariant.withOpacity(0.30)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: t.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: t.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Hogyan szerezhetek XP-t?',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              ruleRow(
                'Napi jutalom: +$_dailyClaimXp XP',
                'Naponta egyszer felvehető a "Mai jutalom" gombbal. A streak is ehhez kötődik.',
                Icons.card_giftcard_rounded,
              ),
              const SizedBox(height: 10),
              ruleRow(
                'Minden poszt: +$_xpPerPost XP',
                'Minden egyes sikeres posztolás után jár XP.',
                Icons.add_circle_outline_rounded,
              ),
              const SizedBox(height: 10),
              ruleRow(
                'Streak (jutalom)',
                'A streak akkor nő, ha minden nap felveszed a napi jutalmat.',
                Icons.local_fire_department_rounded,
              ),
              const SizedBox(height: 10),
              ruleRow(
                'Szintek',
                'Minden ${_xpPerLevel} XP után szintet lépsz.',
                Icons.stars_rounded,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Értem'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ----------------------------
  // UI helpers
  // ----------------------------

  Widget _glassPanel(
    BuildContext context, {
    required Widget child,
    EdgeInsets? padding,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.70),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: t.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _primaryActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    GlobalKey? key,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signedOutTopCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return _glassPanel(
      context,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pecazom', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Közösségi feed, előrejelzés és személyes statisztikák egy felületen.',
            style: t.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          _primaryActionChip(
            context,
            icon: Icons.login,
            label: 'Bejelentkezés',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('A bejelentkezés a jobb felső sarokból érhető el.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------
  // BUILD
  // ----------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const bannerHeight = 50.0;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final user = FirebaseAuth.instance.currentUser;
    final isSignedIn = user != null;

    // ✅ UI oldali tiltás: ha claim folyamatban van, tekintsük úgy, mintha "ma már felvette"
    final claimedOrClaiming = _metrics.claimedToday || _claimingDaily;

    return FadeTransition(
      opacity: _fadeIn,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bannerHeight + bottomInset),
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (n) {
                n.disallowIndicator();
                return false;
              },
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverAppBar(
                    pinned: false,
                    floating: true,
                    snap: true,
                    expandedHeight: 190,
                    backgroundColor: scheme.surface,
                    surfaceTintColor: scheme.surface,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primary.withOpacity(0.30),
                              scheme.tertiary.withOpacity(0.16),
                              scheme.surface,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSignedIn ? 'Áttekintés' : 'Kezdőlap',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isSignedIn
                                      ? 'Üdvözlünk, $_displayName. Itt eléred az előrejelzést, statisztikát és a közösségi feedet.'
                                      : 'Böngészd a közösségi feedet. A teljes funkciókhoz jelentkezz be.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.25,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DailyHubCard(
                            key: _dailyHubKey,
                            displayName: _displayName,
                            isSignedIn: isSignedIn,
                            streakDays: _metrics.streakDays,
                            level: _metrics.level,
                            xpProgress: _metrics.xpProgress,
                            bestWindow: _metrics.bestWindow,
                            challengeText: _metrics.challengeText,
                            challengeProgress: _metrics.challengeProgress,
                            claimedToday: claimedOrClaiming, // ✅
                            onClaim: isSignedIn
                                ? () => _claimDailyReward(user!.uid)
                                : null,
                            onXpInfo: _showXpInfoSheet,
                          ),
                          const SizedBox(height: 18),
                          if (!isSignedIn) ...[
                            _signedOutTopCard(context),
                            const SizedBox(height: 18),
                          ],
                          if (isSignedIn) ...[
                            _sectionHeader(
                              context,
                              title: 'AI előrejelzés',
                              subtitle:
                                  'Ajánlott idő, csali és célhal – strukturáltan.',
                            ),
                            _glassPanel(
                              context,
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                key: _forecastKey,
                                child: const ForecastCard(
                                    lat: 47.4979, lon: 19.0402),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _sectionHeader(
                              context,
                              title: 'Statisztikák',
                              subtitle:
                                  'Személyes eredmények és aktivitás összefoglaló.',
                            ),
                            _glassPanel(
                              context,
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                key: _statsKey,
                                child: ResultsStatsCard(userId: user!.uid),
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          _sectionHeader(
                            context,
                            title: 'Közösség',
                            subtitle: isSignedIn
                                ? 'Oszd meg a fogásod, vagy böngészd a feedet.'
                                : 'Böngészés elérhető, posztoláshoz bejelentkezés szükséges.',
                            trailing: isSignedIn
                                ? _primaryActionChip(
                                    context,
                                    icon: Icons.add,
                                    label: 'Új poszt',
                                    key: _addPostKey,
                                    onPressed: () {
                                      AddPostDialog.show(
                                        context,
                                        onPostAdded: () async {
                                          await _markPostedTodayAndReward(
                                              user!.uid);
                                        },
                                      );
                                    },
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _glassPanel(
                        context,
                        padding: const EdgeInsets.all(14),
                        child: const RepaintBoundary(
                          child: PostList(),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Container(
                        key: _footerKey,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 10),
                        child: Column(
                          children: [
                            Text(
                              'Pecazom v$currentVersion',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Visszajelzés: info@pecazom.hu',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: BannerAdWidget(),
              ),
            ),
          ),

          // ----------------------------
          // STRICT FORCED UPDATE OVERLAY (TOPMOST)
          // ----------------------------
          if (_forceBlocked)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(color: Colors.black54),
              ),
            ),
          if (_forceBlocked)
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Material(
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.system_update_alt_rounded, size: 44),
                            const SizedBox(height: 10),
                            Text(
                              'Frissítés kötelező',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A folytatáshoz frissítened kell az alkalmazást.\n'
                              'Minimum verzió: ${_minVersion ?? "-"}\n'
                              'Jelenlegi: $currentVersion'
                              '${_latestVersion == null ? '' : '\nLegújabb: $_latestVersion'}',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _openStoreStrict,
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Megnyitás a Play Áruházban'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension _ListX<E> on List<E> {
  E? elementAtOrNull(int i) => (i >= 0 && i < length) ? this[i] : null;
}

// ------------------------------------------------------------
// Retention UI: DailyHubCard
// ------------------------------------------------------------

class DailyHubCard extends StatelessWidget {
  final String displayName;
  final bool isSignedIn;

  final int streakDays;
  final int level;
  final double xpProgress;

  final String bestWindow;

  final String challengeText;
  final double challengeProgress;

  final bool claimedToday;
  final VoidCallback? onClaim;

  final VoidCallback onXpInfo;

  const DailyHubCard({
    super.key,
    required this.displayName,
    required this.isSignedIn,
    required this.streakDays,
    required this.level,
    required this.xpProgress,
    required this.bestWindow,
    required this.challengeText,
    required this.challengeProgress,
    required this.claimedToday,
    this.onClaim,
    required this.onXpInfo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withOpacity(0.30),
                scheme.tertiary.withOpacity(0.18),
                scheme.surface.withOpacity(0.88),
              ],
            ),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                blurRadius: 30,
                offset: const Offset(0, 16),
                color: Colors.black.withOpacity(0.10),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSignedIn ? 'Ma neked, $displayName' : 'Ma neked',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                isSignedIn
                    ? 'Napi ritmus, jutalmak és közösség egy felületen.'
                    : 'Böngészhetsz, de a streak és jutalmak bejelentkezéssel érhetők el.',
                style: t.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _miniMetric(
                    context,
                    icon: Icons.local_fire_department_rounded,
                    title: 'Streak',
                    value: isSignedIn ? '$streakDays nap' : '—',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _miniMetric(
                      context,
                      icon: Icons.schedule_rounded,
                      title: 'Mai ablak',
                      value: bestWindow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: scheme.surface.withOpacity(0.70),
                  border: Border.all(
                      color: scheme.outlineVariant.withOpacity(0.24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flag_rounded,
                            color: scheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Mai kihívás',
                          style:
                              t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        if (isSignedIn)
                          Text(
                            challengeProgress >= 1 ? 'Kész' : 'Folyamatban',
                            style: t.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: challengeProgress >= 1
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      challengeText,
                      style: t.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ((isSignedIn ? challengeProgress : 0.0)
                                .clamp(0.0, 1.0)
                            as double),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          isSignedIn ? 'Szint $level' : 'Szintek és XP',
                          style: t.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: ((isSignedIn ? xpProgress : 0.0)
                                      .clamp(0.0, 1.0)
                                  as double),
                              minHeight: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Hogyan szerezhetek XP-t?',
                          onPressed: onXpInfo,
                          icon: Icon(Icons.info_outline_rounded,
                              color: scheme.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (isSignedIn)
                FilledButton.icon(
                  // ✅ claimedToday már tartalmazza a "claiming" állapotot is
                  onPressed: claimedToday ? null : onClaim,
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: Text(claimedToday
                      ? 'Mai jutalom felvéve'
                      : 'Mai jutalom felvétele (+15 XP)'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('A bejelentkezés a jobb felső sarokból érhető el.')),
                    );
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Bejelentkezés a jutalmakért'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface.withOpacity(0.70),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              Text(value,
                  style: t.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Immutable daily metrics model
// ------------------------------------------------------------

@immutable
class _DailyMetrics {
  final int streakDays;
  final int xp;
  final int level;
  final double xpProgress;
  final String bestWindow;
  final String challengeText;
  final double challengeProgress;
  final bool claimedToday;
  final bool postedToday;

  const _DailyMetrics({
    this.streakDays = 0,
    this.xp = 0,
    this.level = 1,
    this.xpProgress = 0,
    this.bestWindow = '06:10–08:20',
    this.challengeText = 'Vedd fel a napi jutalmat.',
    this.challengeProgress = 0,
    this.claimedToday = false,
    this.postedToday = false,
  });
}
