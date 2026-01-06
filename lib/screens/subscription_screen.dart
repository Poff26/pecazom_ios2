import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const String _backendBaseUrl = 'https://catchsense-backend.onrender.com';

  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _sub;

  bool _available = false;
  bool _loading = true;
  bool _purchaseInFlight = false;

  List<ProductDetails> _products = [];
  String? _error;

  // 5 havi csomag (productId-k)
  static const Set<String> _kProductIds = {
    'pecazom_pro_mini',
    'pecazom_pro',
    'pecazom_pro_plus',
    'pecazom_ultra',
    'pecazom_elite',
  };

  static const Map<String, String> _productToPlan = {
    'pecazom_pro_mini': 'PRO_500',
    'pecazom_pro': 'PRO_1000',
    'pecazom_pro_plus': 'PRO_1500',
    'pecazom_ultra': 'PRO_5000',
    'pecazom_elite': 'PRO_10000',
  };

  // ====== CSOMAG BENEFITEK (MIT KAP A FELHASZNÁLÓ) ======

  static const Map<String, PlanBenefit> _benefitsByProductId = {
    'pecazom_pro_mini': PlanBenefit(
      title: 'Pecazom Pro Mini',
      badge: null,
      features: [
        'Napi 2 AI tanács',
        'Reklámmentes használat',
      ],
    ),
    'pecazom_pro': PlanBenefit(
      title: 'Pecazom Pro',
      badge: null,
      features: [
        'Napi 3 AI tanács',
        'Reklámmentes használat',
      ],
    ),
    'pecazom_pro_plus': PlanBenefit(
      title: 'Pecazom Pro Plus',
      badge: 'Plus',
      features: [
        'Napi 4 AI tanács',
        'Reklámmentes használat',
        'Plus jelvény a profilodon',
      ],
    ),
    'pecazom_ultra': PlanBenefit(
      title: 'Pecazom Ultra',
      badge: 'Ultra',
      features: [
        'Napi 8 AI tanács',
        'Reklámmentes használat',
        'Ultra jelvény a profilodon',
      ],
    ),
    'pecazom_elite': PlanBenefit(
      title: 'Pecazom Elite',
      badge: 'Elite',
      features: [
        'Korlátlan napi AI tanács',
        'Reklámmentes használat',
        'Elite jelvény a profilodon',
      ],
    ),
  };

  // ====== /CSOMAG BENEFITEK ======

  @override
  void initState() {
    super.initState();

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e, st) {
        log('purchaseStream error: $e', stackTrace: st);
        if (mounted) setState(() => _error = e.toString());
      },
    );

    _initStore();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _initStore() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final available = await _iap.isAvailable();
    if (!available) {
      setState(() {
        _available = false;
        _loading = false;
        _error = 'A vásárlás nem elérhető ezen az eszközön.';
      });
      return;
    }

    final response = await _iap.queryProductDetails(_kProductIds);
    if (response.error != null) {
      setState(() {
        _available = true;
        _loading = false;
        _error = 'Terméklekérés hiba: ${response.error}';
      });
      return;
    }

    final products = response.productDetails.toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));

    setState(() {
      _available = true;
      _products = products;
      _loading = false;
    });
  }

  Future<void> _buy(ProductDetails product) async {
    if (_purchaseInFlight) return;

    setState(() {
      _purchaseInFlight = true;
      _error = null;
    });

    final purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions: buyNonConsumable (in_app_purchase így kezeli)
    final ok = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

    if (!ok) {
      setState(() {
        _purchaseInFlight = false;
        _error = 'A vásárlás indítása nem sikerült.';
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _error = null;
      _purchaseInFlight = true;
    });
    await _iap.restorePurchases();
    if (mounted) {
      setState(() => _purchaseInFlight = false);
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          setState(() => _purchaseInFlight = true);
          break;

        case PurchaseStatus.error:
          setState(() {
            _purchaseInFlight = false;
            _error = p.error?.message ?? 'Ismeretlen vásárlási hiba';
          });
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
        // 1) backend verify
          final verified = await _verifyWithBackend(p);

          if (!verified) {
            setState(() {
              _purchaseInFlight = false;
              _error = 'A vásárlás ellenőrzése nem sikerült (backend).';
            });
          } else {
            setState(() => _purchaseInFlight = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Előfizetés aktiválva.')),
              );
            }
          }

          // 2) complete purchase (kötelező, különben újra küldi)
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;

        case PurchaseStatus.canceled:
          setState(() {
            _purchaseInFlight = false;
            _error = 'Vásárlás megszakítva.';
          });
          break;
      }
    }
  }

  Future<bool> _verifyWithBackend(PurchaseDetails p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _error = 'Bejelentkezés szükséges.';
      return false;
    }

    final token = await user.getIdToken(true);

    final productId = p.productID;
    final planId = _productToPlan[productId];

    final payload = {
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'productId': productId,
      'planId': planId,
      'purchaseId': p.purchaseID,
      'verification': {
        'source': p.verificationData.source,
        'serverVerificationData': p.verificationData.serverVerificationData,
        'localVerificationData': p.verificationData.localVerificationData,
      },
      'transactionDate': p.transactionDate,
    };

    try {
      final uri = Uri.parse('$_backendBaseUrl/billing/verify');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode != 200) {
        log('verify failed: ${resp.statusCode} ${resp.body}', name: 'Subscription');
        return false;
      }

      final decoded = jsonDecode(resp.body);
      final ok = decoded is Map && decoded['ok'] == true;
      return ok;
    } catch (e, st) {
      log('verify exception: $e', stackTrace: st, name: 'Subscription');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Előfizetés'),
        actions: [
          TextButton(
            onPressed: _purchaseInFlight ? null : _restore,
            child: const Text('Restore'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_available
            ? Center(child: Text(_error ?? 'Store nem elérhető'))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Válassz csomagot',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Havi előfizetések. Aktiválás után a napi AI limit automatikusan a csomagod szerint működik.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 14),

            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            Expanded(
              child: ListView.separated(
                itemCount: _products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = _products[i];
                  final plan = _productToPlan[p.id] ?? '—';
                  final benefit = _benefitsByProductId[p.id];

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header sor: cím + jelvény + ár + vásárlás gomb
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      benefit?.title ?? p.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 4),
                                    if (benefit?.badge != null)
                                      _PlanBadge(text: benefit!.badge!),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Csomag: $plan',
                                      style: t.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    p.price,
                                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: _purchaseInFlight ? null : () => _buy(p),
                                    child: _purchaseInFlight
                                        ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                        : const Text('Előfizetek'),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Benefit lista
                          if (benefit != null) ...[
                            Text(
                              'Mit kapsz?',
                              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            ...benefit.features.map(
                                  (f) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.check_circle, size: 16, color: Colors.green),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(f, style: t.bodyMedium)),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            // fallback
                            Text(p.description, style: t.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Megjegyzés: iOS-en és Androidon a vásárlás ellenőrzése szerveroldalon történik.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ====== Segéd UI komponensek ======

class PlanBenefit {
  final String title;
  final String? badge; // Plus / Ultra / Elite vagy null
  final List<String> features;

  const PlanBenefit({
    required this.title,
    required this.badge,
    required this.features,
  });
}

class _PlanBadge extends StatelessWidget {
  final String text;
  const _PlanBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
