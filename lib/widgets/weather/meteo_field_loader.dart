import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Meteo field loader used by heatmap/grid components.
///
/// This is intentionally defensive:
/// - If URL is missing/invalid -> returns empty bytes
/// - If request fails -> returns empty bytes
///
/// You can later extend it to:
/// - cache responses (memory/disk)
/// - support multiple providers (your backend, third-party tiles, etc.)
/// - parse JSON/grids into points
class MeteoFieldLoader {
  final http.Client _client;

  MeteoFieldLoader({http.Client? client}) : _client = client ?? http.Client();

  /// Loads raw bytes for a meteo "field".
  ///
  /// Parameters are generic so you can map them to your backend query format.
  /// If you already have a known endpoint, use [url] directly.
  Future<Uint8List> loadFieldBytes({
    String? url,
    String? field,
    double? lat,
    double? lon,
    int? zoom,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final resolvedUrl = _resolveUrl(
      url: url,
      field: field,
      lat: lat,
      lon: lon,
      zoom: zoom,
    );

    if (resolvedUrl == null) {
      return Uint8List(0);
    }

    try {
      final uri = Uri.tryParse(resolvedUrl);
      if (uri == null) return Uint8List(0);

      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Uint8List.fromList(res.bodyBytes);
      }
      return Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// Builds a URL if one wasn't given.
  ///
  /// IMPORTANT:
  /// - This default implementation returns null unless [url] is provided.
  /// - You can wire this to your backend later (example commented).
  String? _resolveUrl({
    required String? url,
    required String? field,
    required double? lat,
    required double? lon,
    required int? zoom,
  }) {
    // If caller provided a direct URL, use it.
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }

    // If you have a backend endpoint, you can construct it here.
    //
    // Example (replace with your real endpoint):
    // if (field != null && lat != null && lon != null) {
    //   final z = zoom ?? 8;
    //   return 'https://your-backend.com/meteo/field?field=$field&lat=$lat&lon=$lon&z=$z';
    // }

    // No URL available -> safe fallback.
    return null;
  }

  void close() {
    _client.close();
  }
}
