import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateConfig {
  final String minVersion;
  final String latestVersion;
  final String storeUrl;

  UpdateConfig({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
  });

  factory UpdateConfig.fromJson(Map<String, dynamic> json) {
    final isAndroid = Platform.isAndroid;

    return UpdateConfig(
      minVersion: (isAndroid ? json['min_version_android'] : json['min_version_ios']) as String,
      latestVersion: (isAndroid ? json['latest_version_android'] : json['latest_version_ios']) as String,
      storeUrl: (isAndroid ? json['android_store_url'] : json['ios_store_url']) as String,
    );
  }
}

class UpdateGate {
  // Ide tedd a saját endpointodat:
  static const String configUrl = 'https://YOUR_DOMAIN/update-config.json';

  static Future<void> checkAndBlockIfNeeded(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version; // pl. "1.2.3"

      final cfg = await _fetchConfig();

      final mustUpdate = _isVersionLower(current, cfg.minVersion);
      final shouldUpdate = _isVersionLower(current, cfg.latestVersion);

      if (!context.mounted) return;

      if (mustUpdate) {
        await _showForceDialog(context, cfg.storeUrl);
      } else if (shouldUpdate) {
        await _showSoftDialog(context, cfg.storeUrl);
      }
    } catch (_) {
      // Ha nem elérhető a config (nincs net, server down),
      // tipikusan hagyjuk továbbmenni az appot.
      // (Ha üzletileg kötelező: itt dönthetsz "block" mellett is.)
    }
  }

  static Future<UpdateConfig> _fetchConfig() async {
    final res = await http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Config fetch failed: ${res.statusCode}');
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return UpdateConfig.fromJson(jsonMap);
  }

  /// Visszaadja, hogy a aVersion < bVersion (szemver: "1.2.10")
  static bool _isVersionLower(String aVersion, String bVersion) {
    List<int> parse(String v) => v.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final a = parse(aVersion);
    final b = parse(bVersion);

    final maxLen = (a.length > b.length) ? a.length : b.length;
    while (a.length < maxLen) a.add(0);
    while (b.length < maxLen) b.add(0);

    for (int i = 0; i < maxLen; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false;
  }

  static Future<void> _showForceDialog(BuildContext context, String storeUrl) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // <- nem zárható
      builder: (_) => WillPopScope(
        onWillPop: () async => false, // <- back gomb se zárja
        child: AlertDialog(
          title: const Text('Frissítés szükséges'),
          content: const Text('A folytatáshoz frissítened kell az alkalmazást.'),
          actions: [
            ElevatedButton(
              onPressed: () => _openStore(storeUrl),
              child: const Text('Frissítés'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showSoftDialog(BuildContext context, String storeUrl) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Frissítés elérhető'),
        content: const Text('Elérhető egy új verzió. Javasolt frissíteni.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Később'),
          ),
          ElevatedButton(
            onPressed: () => _openStore(storeUrl),
            child: const Text('Frissítés'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openStore(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Ha nem nyílik meg, itt kezelheted (toast/snackbar)
    }
  }
}
