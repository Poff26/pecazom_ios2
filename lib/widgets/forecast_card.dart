// ✅ lib/widgets/forecast_card.dart
// ForecastCard — PLAN FIRST + UTÁNA AI SZINT / REKLÁM (Rewarded)
// - Napi keret elfogyása esetén: választható AI szintből vagy reklám megtekintéssel 1 extra lekérés
// - Plan ID helyett megjelenített csomagnevek:
//   Alap csomag, Pecazom Pro Mini, Pecazom Pro, Pecazom Pro Plus, Pecazom Ultra, Pecazom Elite
//
// FONTOS:
// 1) main.dart-ben legyen: await MobileAds.instance.initialize();
// 2) Rewarded ad unit id: ca-app-pub-6845395018275004/6402649363
// 3) Backend oldalon az override header (X-AI-PAID vagy X-AI-AD) esetén NEM szabad incrementelni a napi kvótát.

import 'dart:ui';
import 'dart:convert';
import 'dart:developer';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ADS (Rewarded)
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ForecastCard extends StatefulWidget {
  final double lat;
  final double lon;
  final String? baseUrlOverride;

  const ForecastCard({
    super.key,
    required this.lat,
    required this.lon,
    this.baseUrlOverride,
  });

  @override
  State<ForecastCard> createState() => _ForecastCardState();
}

class _AppConfig {
  static const String defaultBackendBaseUrl =
      'https://catchsense-backend.onrender.com';

  static const String subscriptionRouteName = '/subscription';

  static const int aiForecastCostLevel = 2;

  /// Backend endpoint ami visszaadja a plan status-t
  static const String planStatusPath = '/plan-status';

  /// Paid override jelzés a backend felé
  static const String paidOverrideHeader = 'X-AI-PAID';
  static const String paidOverrideValue = '1';

  /// Ad override jelzés a backend felé
  static const String adOverrideHeader = 'X-AI-AD';
  static const String adOverrideValue = '1';

  /// PLAN IDs (amit Firestore/Backend ad)
  static const String planFree = 'FREE';
  static const String planProMini = 'PRO_MINI';
  static const String planPro = 'PRO';
  static const String planProPlus = 'PRO_PLUS';
  static const String planUltra = 'ULTRA';
  static const String planElite = 'ELITE';

  /// ✅ Rewarded Ad Unit ID (PROD)
  static const String rewardedAdUnitIdAndroid =
      'ca-app-pub-6845395018275004/6402649363';

  /// iOS-hez külön unit id kell majd (ha lesz iOS)
  static const String rewardedAdUnitIdIos =
      'ca-app-pub-3940256099942544/1712485313'; // placeholder
}

class _ForecastCardState extends State<ForecastCard> {
  Future<ForecastOut>? _future;
  bool _loading = false;

  // plan meta
  String _planId = _AppConfig.planFree;
  int? _dailyLimit;
  int? _used;
  int? _remaining;
  bool get _unlimited => _dailyLimit == null;

  String get _baseUrl => (widget.baseUrlOverride?.trim().isNotEmpty ?? false)
      ? widget.baseUrlOverride!.trim()
      : _AppConfig.defaultBackendBaseUrl;

  // Rewarded Ad state
  RewardedAd? _rewardedAd;
  bool _adLoading = false;

  // ---------------------------
  // Lifecycle
  // ---------------------------

  @override
  void initState() {
    super.initState();
    _loadRewardedAd();
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    super.dispose();
  }

  // ---------------------------
  // Safe setState (CRITICAL FIX)
  // ---------------------------
  //
  // A setState callback NEM LEHET async, és nem adhat vissza Future-t.
  // Ez a signature direkt void Function() -> ha valaki async-ot ír bele,
  // a Dart analyzer/fordító már jelzi, és runtime hiba sem lesz.
  //
  void _setStateSafe(Function fn) {
    if (!mounted) return;

    setState(() {
      // FONTOS: itt nem "return"-öljük fn eredményét,
      // így akkor sem ad vissza Future-t a setState callback,
      // ha valaki véletlenül async closure-t adott át.
      final r = fn();
      if (r is Future) {
        // Ne dobd el a Future-t hiba nélkül: logoljuk és engedjük futni.
        // (Itt NEM await-elünk, mert setState callback nem lehet async.)
        unawaited(r);
      }
    });
  }


  // ---------------------------
  // Plan display name
  // ---------------------------

  String _planDisplayName(String rawPlanId) {
    final p = rawPlanId.trim().toUpperCase();
    switch (p) {
      case _AppConfig.planFree:
        return 'Alap csomag';
      case _AppConfig.planProMini:
        return 'Pecazom Pro Mini';
      case _AppConfig.planPro:
        return 'Pecazom Pro';
      case _AppConfig.planProPlus:
        return 'Pecazom Pro Plus';
      case _AppConfig.planUltra:
        return 'Pecazom Ultra';
      case _AppConfig.planElite:
        return 'Pecazom Elite';
      default:
        return rawPlanId.isEmpty ? 'Alap csomag' : rawPlanId;
    }
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? null;
  }

  bool _looksLikeQuotaError(String msg) {
    final m = msg.toLowerCase();
    return m.contains('429') ||
        m.contains('limit') ||
        m.contains('keret') ||
        m.contains('quota') ||
        m.contains('túl sok') ||
        m.contains('too many requests') ||
        m.contains('napi ai');
  }

  void _openSubscriptionScreen() {
    Navigator.pushNamed(context, _AppConfig.subscriptionRouteName);
  }

  void _showUpgradeDialog({String? message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elfogyott a napi keret'),
        content: Text(
          message ??
              'A csomagod napi AI kerete elfogyott.\n\n'
                  'Válts nagyobb csomagra, vagy kérj extra lekérést AI szintből / reklám megtekintésével.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Később'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _openSubscriptionScreen();
            },
            child: const Text('Csomagok'),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Rewarded Ad
  // ---------------------------

  String _rewardedUnitIdForPlatform() {
    // Ha később iOS: Platform.isIOS alapján cseréld.
    return _AppConfig.rewardedAdUnitIdAndroid;
  }

  void _loadRewardedAd() {
    if (_adLoading) return;
    _adLoading = true;

    RewardedAd.load(
      adUnitId: _rewardedUnitIdForPlatform(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _adLoading = false;

          _rewardedAd?.dispose();
          _rewardedAd = ad;

          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewardedAd();
            },
          );

          _setStateSafe(() {}); // UI frissítés: adReady
        },
        onAdFailedToLoad: (err) {
          _adLoading = false;
          _rewardedAd = null;
          log('RewardedAd failed to load: $err');
          _setStateSafe(() {}); // UI frissítés: adReady
        },
      ),
    );
  }

  Future<bool> _showRewardedAdAndWaitReward() async {
    if (_rewardedAd == null) {
      _loadRewardedAd();
      return false;
    }

    final completer = Completer<bool>();
    bool rewarded = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        if (!completer.isCompleted) completer.complete(rewarded);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        rewarded = true;
      },
    );

    return completer.future;
  }

  // ---------------------------
  // Firestore: aiLevel levonás / refund (tranzakció)
  // ---------------------------

  Future<int> _getAiLevel(String uid) async {
    final doc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    return (data['aiLevel'] as num?)?.toInt() ?? 0;
  }

  Future<bool> _deductAiLevel({
    required String uid,
    int cost = _AppConfig.aiForecastCostLevel,
  }) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return false;

      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['aiLevel'] as num?)?.toInt() ?? 0;

      if (current < cost) return false;

      tx.update(ref, {
        'aiLevel': current - cost,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Future<void> _refundAiLevel({
    required String uid,
    int amount = _AppConfig.aiForecastCostLevel,
  }) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    await FirebaseFirestore.instance.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['aiLevel'] as num?)?.toInt() ?? 0;

      tx.update(ref, {
        'aiLevel': current + amount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------
  // Backend: plan status
  // ---------------------------

  Future<void> _refreshPlanStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Bejelentkezés szükséges.');

    final token = await user.getIdToken(true);
    final uri = Uri.parse('$_baseUrl${_AppConfig.planStatusPath}');

    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        _tryExtractDetail(resp.body) ??
            'Plan status hiba: HTTP ${resp.statusCode}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Érvénytelen plan status válasz.');
    }

    // ✅ setState csak sync (NEM async)
    _setStateSafe(() {
      _planId = (decoded['planId'] ?? _planId).toString();
      _dailyLimit = _asIntOrNull(decoded['dailyLimit']);
      _used = _asIntOrNull(decoded['usedToday']);
      _remaining = _asIntOrNull(decoded['remainingToday']);
    });
  }

  String? _tryExtractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return null;
  }

  // ---------------------------
  // AI szint info bottom sheet (+ Reklám)
  // ---------------------------

  void _openEarnAiLevelSheet({
    required int aiLevel,
    required int cost,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.70,
          minChildSize: 0.40,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return ClipRRect(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.94),
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hogyan szerezhetek extra lekérést?',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Egyenleg: $aiLevel • 1 extra lekérés: $cost AI szint vagy 1 reklám megtekintése',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _InfoCard(
                        title: 'Extra lekérés – lehetőségek',
                        icon: Icons.bolt_rounded,
                        lines: const [
                          'AI szintből: ha elfogyott a napi keret, 2 AI szintért kérhetsz 1 extra lekérést.',
                          'Reklám megtekintésével: 1 Rewarded reklám után 1 extra lekérés aktiválódik.',
                          'Csomagváltással: nagyobb napi keret és kényelmesebb használat.',
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InfoCard(
                        title: 'AI szint gyűjtés',
                        icon: Icons.emoji_events_rounded,
                        lines: const [
                          'Posztolj fogást a közösségbe (napi bónusz).',
                          'Vedd fel a napi jutalmat (streak).',
                          'Aktivitással fejlődsz, a rendszer pedig jutalmaz.',
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Bezárás'),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _openSubscriptionScreen();
                              },
                              icon: const Icon(Icons.local_mall_rounded),
                              label: const Text('Csomagok'),
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------
  // Szép dialog: quota elfogyott -> AI szint / Reklám / Csomag
  // ---------------------------

  Future<_ExtraChoice> _askExtraChoice({
    required int aiLevel,
    required int cost,
    required bool adReady,
  }) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return (await showDialog<_ExtraChoice>(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.info_outline_rounded, color: cs.error),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Elfogyott a napi keret',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'A csomagod napi AI lekérési kerete elfogyott. Válassz egy lehetőséget:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.78),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.workspace_premium_rounded,
                title: 'AI szintből',
                subtitle: '$cost kredit • 1 extra lekérés',
                enabled: true,
                onTap: () => Navigator.pop(context, _ExtraChoice.aiLevel),
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.ondemand_video_rounded,
                title: 'Reklám megtekintése',
                subtitle:
                adReady ? '1 reklám • 1 extra lekérés' : 'Jelenleg nem elérhető',
                enabled: adReady,
                onTap:
                adReady ? () => Navigator.pop(context, _ExtraChoice.ad) : null,
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.local_mall_rounded,
                title: 'Csomagok',
                subtitle: 'Nagyobb napi keret',
                enabled: true,
                onTap: () => Navigator.pop(context, _ExtraChoice.plans),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Jelenlegi AI szint: $aiLevel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, _ExtraChoice.cancel),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Mégse'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )) ??
        _ExtraChoice.cancel;
  }

  // ---------------------------
  // Main action: Lekérés
  // ---------------------------

  Future<void> _onPressRequest() async {
    if (_loading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _setStateSafe(() => _loading = true);

    bool deducted = false;
    final cost = _AppConfig.aiForecastCostLevel;

    try {
      // 1) PLAN FIRST
      await _refreshPlanStatus();

      final remaining = _remaining ?? 0;

      // 2) Ha van keret a csomagban -> normál lekérés
      if (remaining > 0 || _unlimited) {
        final fut = ForecastService(baseUrl: _baseUrl).fetchCatchForecast(
          lat: widget.lat,
          lon: widget.lon,
          paidOverride: false,
          adOverride: false,
        );

        _setStateSafe(() => _future = fut);

        final res = await fut;
        _applyPlanFromForecast(res);
        return;
      }

      // 3) Nincs keret -> AI szint / reklám / csomag
      final aiLevel = await _getAiLevel(user.uid);
      final adReady = _rewardedAd != null;

      final choice = await _askExtraChoice(
        aiLevel: aiLevel,
        cost: cost,
        adReady: adReady,
      );

      if (choice == _ExtraChoice.cancel) return;

      if (choice == _ExtraChoice.plans) {
        _openSubscriptionScreen();
        return;
      }

      // 3/A) Reklám
      if (choice == _ExtraChoice.ad) {
        final ok = await _showRewardedAdAndWaitReward();
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A reklám jutalom nem érkezett meg.')),
          );
          return;
        }

        final fut = ForecastService(baseUrl: _baseUrl).fetchCatchForecast(
          lat: widget.lat,
          lon: widget.lon,
          paidOverride: true,
          adOverride: true,
        );

        _setStateSafe(() => _future = fut);

        final res = await fut;
        _applyPlanFromForecast(res);
        return;
      }

      // 3/B) AI szint
      if (aiLevel < cost) {
        _openEarnAiLevelSheet(aiLevel: aiLevel, cost: cost);
        return;
      }

      final did = await _deductAiLevel(uid: user.uid, cost: cost);
      if (!did) {
        final nowLevel = await _getAiLevel(user.uid);
        _openEarnAiLevelSheet(aiLevel: nowLevel, cost: cost);
        return;
      }
      deducted = true;

      final fut = ForecastService(baseUrl: _baseUrl).fetchCatchForecast(
        lat: widget.lat,
        lon: widget.lon,
        paidOverride: true,
        adOverride: false,
      );

      _setStateSafe(() => _future = fut);

      final res = await fut;
      _applyPlanFromForecast(res);
    } catch (e, st) {
      log('Forecast error', error: e, stackTrace: st);

      if (deducted) {
        try {
          await _refundAiLevel(uid: user.uid, amount: cost);
        } catch (re) {
          log('Refund failed', error: re);
        }
      }

      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');

      if (_looksLikeQuotaError(msg)) {
        _showUpgradeDialog(message: msg);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      _setStateSafe(() => _loading = false);
    }
  }

  void _applyPlanFromForecast(ForecastOut res) {
    final p = res.plan;
    if (p == null) return;

    _setStateSafe(() {
      _planId = (p['planId'] ?? _planId).toString();
      _dailyLimit = _asIntOrNull(p['dailyLimit']);
      _used = _asIntOrNull(p['usedToday']);
      _remaining = _asIntOrNull(p['remainingToday']);
    });
  }

  // ---------------------------
  // UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (user == null) {
      return _SectionCard(
        title: 'AI előrejelzés',
        subtitle: 'Bejelentkezés szükséges az előrejelzéshez.',
        trailing: const SizedBox.shrink(),
        child: const SizedBox.shrink(),
      );
    }

    final userDocStream =
    FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final aiLevel = (data['aiLevel'] as num?)?.toInt() ?? 0;
        final rawPlanId = (data['planId'] ?? _planId).toString();
        final planName = _planDisplayName(rawPlanId);

        final subtitle = _future == null
            ? 'Ajánlott idő, csali és célhal – strukturáltan.'
            : _unlimited
            ? 'Csomag: $planName'
            : 'Mai keret: ${_used ?? '-'} / ${_dailyLimit ?? '-'} • Maradt: ${_remaining ?? 0} • Csomag: $planName';

        return _SectionCard(
          title: 'AI előrejelzés',
          subtitle: subtitle,
          trailing: _MetaBadge(
            planName: planName,
            aiLevel: aiLevel,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _onPressRequest,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(_future == null ? 'Lekérés' : 'Frissítés'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => _openEarnAiLevelSheet(
                    aiLevel: aiLevel,
                    cost: _AppConfig.aiForecastCostLevel,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: const Text('Hogyan szerezhetek extra lekérést?'),
                ),
              ),
              const SizedBox(height: 10),
              if ((_planDisplayName(rawPlanId) == 'Alap csomag') &&
                  (_remaining != null)) ...[
                _InlineNote(
                  text: (_remaining ?? 0) > 0
                      ? 'Alap csomag: ma még van ingyenes lekérésed.'
                      : 'Alap csomag: a mai ingyenes lekérés elfogyott. További lekérés AI szintből vagy reklám megtekintésével kérhető.',
                ),
                const SizedBox(height: 10),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _future == null
                    ? _EmptyStateHint(
                  icon: Icons.auto_awesome,
                  text:
                  'Nyomj a „Lekérés” gombra. Először a csomag keretét használjuk. Ha elfogy, AI szintből vagy reklám megtekintésével tudsz extra lekérést kérni.',
                )
                    : FutureBuilder<ForecastOut>(
                  future: _future,
                  builder: (context, snap2) {
                    if (snap2.connectionState ==
                        ConnectionState.waiting) {
                      return const _ForecastLoading();
                    }

                    if (snap2.hasError) {
                      final msg = snap2.error
                          .toString()
                          .replaceFirst('Exception: ', '');
                      return _InlineError(message: msg);
                    }

                    if (!snap2.hasData) {
                      return const _InlineError(
                        message:
                        'Nem érkezett válasz az előrejelzéshez.',
                      );
                    }

                    final res = snap2.data!;
                    final tipsMerged = <String>[
                      ...res.baitTips,
                      ...res.spotTips,
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ChanceRow(
                          percent: res.chance,
                          label: 'kapási esély',
                        ),
                        const SizedBox(height: 10),
                        if (res.why.isNotEmpty) ...[
                          Text(
                            res.why.first,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.82),
                              height: 1.35,
                            ),
                          ),
                          if (res.why.length > 1) ...[
                            const SizedBox(height: 10),
                            ...res.why.skip(1).map(
                                  (t) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 6),
                                child: _Bullet(text: t),
                              ),
                            ),
                          ],
                        ] else ...[
                          Text(
                            'Nincs részletes indoklás a válaszban.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.72),
                            ),
                          ),
                        ],
                        if (tipsMerged.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Tippek',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...tipsMerged.map(
                                (t) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _Bullet(text: t),
                            ),
                          ),
                        ],
                        if (res.bestTimeWindows.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Ajánlott idősávok',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...res.bestTimeWindows.map(
                                (w) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _Bullet(
                                text:
                                '${w.fromTime}–${w.toTime} • ${w.chance}%',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          res.llmUsed
                              ? 'AI: LLM aktív'
                              : 'AI: fallback (LLM inaktív vagy parse hiba)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _ExtraChoice { cancel, aiLevel, ad, plans }

/// ------------------------------------------------------------
/// MODELLEK
/// ------------------------------------------------------------

class BestWindow {
  final String fromTime;
  final String toTime;
  final int chance;

  BestWindow({
    required this.fromTime,
    required this.toTime,
    required this.chance,
  });

  factory BestWindow.fromJson(Map<String, dynamic> j) => BestWindow(
    fromTime: (j['from_time'] ?? '').toString(),
    toTime: (j['to_time'] ?? '').toString(),
    chance: ForecastOut._toInt(j['chance']),
  );
}

class ForecastOut {
  final int chance;
  final double confidence;
  final List<BestWindow> bestTimeWindows;
  final List<String> why;
  final List<String> baitTips;
  final List<String> spotTips;
  final Map<String, dynamic> signals;
  final Map<String, dynamic> meta;

  ForecastOut({
    required this.chance,
    required this.confidence,
    required this.bestTimeWindows,
    required this.why,
    required this.baitTips,
    required this.spotTips,
    required this.signals,
    required this.meta,
  });

  factory ForecastOut.fromJson(Map<String, dynamic> j) {
    final btw = (j['best_time_windows'] as List? ?? [])
        .map((e) => BestWindow.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ForecastOut(
      chance: _toInt(j['chance']),
      confidence: _toDouble(j['confidence']),
      bestTimeWindows: btw,
      why: (j['why'] as List? ?? []).map((e) => e.toString()).toList(),
      baitTips: (j['bait_tips'] as List? ?? []).map((e) => e.toString()).toList(),
      spotTips: (j['spot_tips'] as List? ?? []).map((e) => e.toString()).toList(),
      signals: Map<String, dynamic>.from(j['signals'] ?? {}),
      meta: Map<String, dynamic>.from(j['meta'] ?? {}),
    );
  }

  Map<String, dynamic>? get plan {
    final p = meta['plan'];
    if (p is Map) return Map<String, dynamic>.from(p);
    return null;
  }

  bool get llmUsed => meta['llm_used'] == true;

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// ------------------------------------------------------------
/// SERVICE — Bearer token + paid override header (+ ad header)
/// ------------------------------------------------------------

class ForecastService {
  final String baseUrl;

  ForecastService({required this.baseUrl});

  Future<ForecastOut> fetchCatchForecast({
    required double lat,
    required double lon,
    required bool paidOverride,
    required bool adOverride,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Bejelentkezés szükséges.');

    final token = await user.getIdToken(true);

    final uri = Uri.parse('$baseUrl/catch-forecast');
    final body = jsonEncode({
      'lat': lat,
      'lon': lon,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    if (paidOverride) {
      headers[_AppConfig.paidOverrideHeader] = _AppConfig.paidOverrideValue;
    }
    if (adOverride) {
      headers[_AppConfig.adOverrideHeader] = _AppConfig.adOverrideValue;
    }

    final resp = await http.post(uri, headers: headers, body: body);

    log('catch-forecast HTTP ${resp.statusCode}: ${resp.body}');

    if (resp.statusCode == 401) {
      throw Exception('Nincs jogosultság (401). Token hiányzik/hibás.');
    }
    if (resp.statusCode == 429) {
      throw Exception(_tryExtractDetail(resp.body) ?? 'Napi AI limit elérve.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        _tryExtractDetail(resp.body) ?? 'Backend hiba: HTTP ${resp.statusCode}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Érvénytelen válaszformátum a backendtől.');
    }

    return ForecastOut.fromJson(decoded);
  }

  String? _tryExtractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return null;
  }
}

/// ------------------------------------------------------------
/// UI
/// ------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final String planName;
  final int aiLevel;

  const _MetaBadge({
    required this.planName,
    required this.aiLevel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            '$planName • AI: $aiLevel',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  final String text;
  const _InlineNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.2,
          color: cs.onSurface.withOpacity(0.78),
        ),
      ),
    );
  }
}

class _EmptyStateHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyStateHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.72),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastLoading extends StatelessWidget {
  const _ForecastLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Előrejelzés készítése…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.85),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChanceRow extends StatelessWidget {
  final int percent;
  final String label;

  const _ChanceRow({required this.percent, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.set_meal, color: cs.onPrimaryContainer, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$percent%',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: cs.onSurface.withOpacity(0.82),
      height: 1.25,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.65),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> lines;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lines.map(
                (x) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.70),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      x,
                      style: t.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.80),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(enabled ? 0.55 : 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(enabled ? 0.35 : 0.20),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled
                    ? cs.primaryContainer.withOpacity(0.75)
                    : cs.surfaceContainerHighest.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: enabled
                    ? cs.onPrimaryContainer
                    : cs.onSurface.withOpacity(0.45),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: enabled
                          ? cs.onSurface.withOpacity(0.90)
                          : cs.onSurface.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? cs.onSurface.withOpacity(0.65)
                          : cs.onSurface.withOpacity(0.40),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withOpacity(enabled ? 0.55 : 0.25),
            ),
          ],
        ),
      ),
    );
  }
}
