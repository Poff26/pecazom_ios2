import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fishing_app_flutter/widgets/weather/meteo_field_loader.dart';

enum FieldType { rainChance, pressureMb, biteIndex }

class SamplePoint {
  final LatLng latLng;
  final double value01; // 0..1
  const SamplePoint(this.latLng, this.value01);
}

class WeatherGridService {
  final WeatherService weatherService;

  // ---- TUNABLES ----
  final Duration ttl;
  final double tileDeg; // ~0.02 => kb. 2km lat irányban; HU-hoz jó kompromisszum
  final int concurrency;

  WeatherGridService({
    required this.weatherService,
    this.ttl = const Duration(minutes: 15),
    this.tileDeg = 0.02,
    this.concurrency = 4,
  });

  // Cache: tileKey -> entry
  final Map<String, _CacheEntry> _cache = {};

  Future<List<SamplePoint>> loadFieldPoints({
    required LatLngBounds bounds,
    required int gridN,
    required int hourIndex,
    required FieldType field,
  }) async {
    final pts = _gridPoints(bounds, gridN);

    // Batch + limit concurrency
    final results = <_GridCellResult>[];
    int i = 0;
    while (i < pts.length) {
      final batch = pts.skip(i).take(concurrency).toList();
      final batchRes = await Future.wait(batch.map((p) => _fetchAt(p)));
      results.addAll(batchRes);
      i += concurrency;
    }

    final rawValues = results
        .map((r) => _extractFieldValue(r.weather, hourIndex, field))
        .toList();

    // Robosztus normalizáció: 5% és 95% percentilis (kevésbé zajos, stabilabb heatmap)
    final (minV, maxV) = _robustMinMax(rawValues, lowP: 0.05, highP: 0.95);

    double norm(double v) {
      final denom = (maxV - minV);
      if (denom.abs() < 1e-9) return 0.0;
      return ((v - minV) / denom).clamp(0.0, 1.0);
    }

    return List.generate(results.length, (idx) {
      return SamplePoint(results[idx].latLng, norm(rawValues[idx]));
    });
  }

  // ---- helpers ----

  List<LatLng> _gridPoints(LatLngBounds b, int n) {
    final sw = b.southwest;
    final ne = b.northeast;

    double lerp(double a, double bb, double t) => a + (bb - a) * t;

    final out = <LatLng>[];
    for (int y = 0; y < n; y++) {
      final ty = n == 1 ? 0.5 : y / (n - 1);
      final lat = lerp(sw.latitude, ne.latitude, ty);
      for (int x = 0; x < n; x++) {
        final tx = n == 1 ? 0.5 : x / (n - 1);
        final lon = lerp(sw.longitude, ne.longitude, tx);
        out.add(LatLng(lat, lon));
      }
    }
    return out;
  }

  String _tileKey(LatLng p) {
    // tile index: floor(lat/tileDeg), floor(lon/tileDeg)
    final latI = (p.latitude / tileDeg).floor();
    final lonI = (p.longitude / tileDeg).floor();
    return 't:$latI:$lonI';
  }

  Future<_GridCellResult> _fetchAt(LatLng p) async {
    final k = _tileKey(p);
    final now = DateTime.now();

    final cached = _cache[k];
    if (cached != null && now.difference(cached.fetchedAt) <= ttl) {
      return _GridCellResult(p, cached.weather);
    }

    // Valós adat lekérés (forecast is legyen benne, ha a WeatherResponse tartalmazza)
    final w = await weatherService.fetchCurrentWeather(lat: p.latitude, lon: p.longitude);

    _cache[k] = _CacheEntry(weather: w, fetchedAt: now);
    return _GridCellResult(p, w);
  }

  double _extractFieldValue(WeatherResponse w, int hourIndex, FieldType field) {
    final hours = w.forecast.forecastday.first.hour;
    final idx = hourIndex.clamp(0, max(0, hours.length - 1));
    final h = hours[idx.toInt()];

    switch (field) {
      case FieldType.rainChance:
        return h.chanceOfRain.toDouble(); // 0..100
      case FieldType.pressureMb:
        return h.pressureMb; // mb
      case FieldType.biteIndex:
      // Heurisztika maradhat, de picit stabilabb súlyozással:
        final rain = h.chanceOfRain.toDouble(); // 0..100
        final p = h.pressureMb;
        final temp = h.tempC;

        final currentP = w.current.pressureMb;
        final pDelta = (p - currentP).abs();

        final rainScore = (1.0 - (rain / 100.0)).clamp(0.0, 1.0);
        final pScore = (1.0 - (pDelta / 6.0)).clamp(0.0, 1.0); // kicsit toleránsabb (stabilabb)
        final tempScore = _tempScore(temp);

        // picit kiegyensúlyozottabb, kevésbé ugrál
        return (0.40 * rainScore) + (0.35 * pScore) + (0.25 * tempScore);
    }
  }

  double _tempScore(double temp) {
    // 12..24 ideális, széleken fokozatosan esik
    if (temp >= 12 && temp <= 24) return 1.0;
    if (temp < 12) return (temp / 12.0).clamp(0.0, 1.0);
    return (1.0 - ((temp - 24.0) / 10.0)).clamp(0.0, 1.0);
  }

  (double, double) _robustMinMax(List<double> values, {required double lowP, required double highP}) {
    if (values.isEmpty) return (0.0, 1.0);
    final sorted = [...values]..sort();
    int idx(double p) => (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    final lo = sorted[idx(lowP)];
    final hi = sorted[idx(highP)];
    // ha hi==lo, essünk vissza sima min/max-ra
    if ((hi - lo).abs() < 1e-9) {
      return (sorted.first, sorted.last);
    }
    return (lo, hi);
  }
}

class _CacheEntry {
  final WeatherResponse weather;
  final DateTime fetchedAt;
  const _CacheEntry({required this.weather, required this.fetchedAt});
}

class _GridCellResult {
  final LatLng latLng;
  final WeatherResponse weather;
  const _GridCellResult(this.latLng, this.weather);
}
