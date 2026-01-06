// lib/services/overpass_service.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum FishingLayerMode {
  fishingSpots,
  fishableWaters,
  allWaters,
}

class OverpassFishingSpot {
  final String id; // "way_123", "node_456", "relation_789"
  final String name;
  final LatLng position;
  final Map<String, dynamic> tags;

  OverpassFishingSpot({
    required this.id,
    required this.name,
    required this.position,
    required this.tags,
  });
}

class OverpassService {
  OverpassService({List<String>? endpoints})
      : endpoints = endpoints ??
      const [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://overpass.openstreetmap.ru/api/interpreter',
      ];

  final List<String> endpoints;

  // Biztonsági korlátok
  static const int _maxOut = 3500;

  // Ha túl nagy területet nézel, ne próbálkozzon (Overpass úgyis elvérzik)
  // (fok^2, kb. “túl nagy viewport” küszöb)
  static const double _maxAreaDeg2 = 1.20;

  // Tiling
  static const int _tileN = 2; // 2x2 tile (gyors, jó kompromisszum)
  static const int _timeoutSeconds = 18;

  Future<List<OverpassFishingSpot>> fetchBbox({
    required double south,
    required double west,
    required double north,
    required double east,
    required FishingLayerMode mode,
    int timeoutSeconds = _timeoutSeconds,
  }) async {
    // Normalizálás (biztos, ami biztos)
    final s = math.min(south, north);
    final n = math.max(south, north);
    final w = math.min(west, east);
    final e = math.max(west, east);

    final area = (n - s).abs() * (e - w).abs();
    if (area > _maxAreaDeg2) {
      // túl nagy nézet -> sok adat -> lassú/timeout
      return <OverpassFishingSpot>[];
    }

    // Kisebb területeket egyben is le lehet kérni
    // de biztonságosabb mindig tile-olni, mert így stabil.
    final tiles = _splitBbox(s, w, n, e, _tileN);

    // Endpoint fallback + tile merge
    Exception? lastErr;
    for (final ep in endpoints) {
      try {
        final merged = <OverpassFishingSpot>[];
        final seen = <String>{};

        // sorban kérjük le a tile-okat (kevesebb throttle, stabilabb)
        // ha kell, később lehet párhuzamosítani 2-esével, de előbb stabil legyen
        for (final t in tiles) {
          final query = _buildQuery(
            south: t.south,
            west: t.west,
            north: t.north,
            east: t.east,
            mode: mode,
            timeoutSeconds: timeoutSeconds,
          );

          final resp = await http
              .post(
            Uri.parse(ep),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'Accept': 'application/json',
              'Accept-Encoding': 'gzip',
            },
            body: 'data=${Uri.encodeComponent(query)}',
          )
              .timeout(Duration(seconds: timeoutSeconds + 4));

          if (resp.statusCode != 200) {
            throw Exception('Overpass error ${resp.statusCode}: ${resp.body}');
          }

          final data = json.decode(resp.body) as Map<String, dynamic>;
          final elements = (data['elements'] as List?) ?? const [];

          for (final el in elements) {
            if (el is! Map<String, dynamic>) continue;
            final type = (el['type'] as String?) ?? 'unknown';
            final idNum = el['id'];
            if (idNum == null) continue;

            double? lat = (el['lat'] as num?)?.toDouble();
            double? lon = (el['lon'] as num?)?.toDouble();

            final center = el['center'];
            if ((lat == null || lon == null) && center is Map<String, dynamic>) {
              lat = (center['lat'] as num?)?.toDouble();
              lon = (center['lon'] as num?)?.toDouble();
            }
            if (lat == null || lon == null) continue;

            final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

            // Ne engedjünk be “zajt” allWaters módban
            if (mode == FishingLayerMode.allWaters && !_isUsefulWater(tags)) continue;

            final id = '${type}_$idNum';
            if (!seen.add(id)) continue;

            final name = _pickName(tags) ?? _fallbackName(tags, mode);

            merged.add(
              OverpassFishingSpot(
                id: id,
                name: name,
                position: LatLng(lat, lon),
                tags: tags,
              ),
            );

            if (merged.length >= _maxOut) break;
          }

          if (merged.length >= _maxOut) break;
        }

        return merged;
      } catch (e) {
        lastErr = Exception('Endpoint failed: $ep | $e');
      }
    }

    throw lastErr ?? Exception('Overpass failed on all endpoints.');
  }

  // ---------------------------
  // Query: poligon fókusz + qt gyorsítás
  // ---------------------------

  String _buildQuery({
    required double south,
    required double west,
    required double north,
    required double east,
    required FishingLayerMode mode,
    required int timeoutSeconds,
  }) {
    // Lényeg: NE kérjünk waterway=stream/drain/river/canal vonalakat.
    // Ezek tömegesek és megölik a teljesítményt.
    //
    // Horgászvizekhez a legértékesebb:
    // - natural=water (tó, tározó, stb.) [way+relation]
    // - waterway=riverbank (folyó poligon)
    //
    // fishingSpots maradhat POI.

    String body;
    switch (mode) {
      case FishingLayerMode.fishingSpots:
        body = '''
          nwr["leisure"="fishing"]($south,$west,$north,$east);
        ''';
        break;

      case FishingLayerMode.fishableWaters:
      // széles, de még mindig poligon fókusz
        body = '''
          (
            nwr["natural"="water"]($south,$west,$north,$east);
            nwr["waterway"="riverbank"]($south,$west,$north,$east);

            // ha mégis van fishing tag a poligonon, az is jön
            nwr["natural"="water"]["fishing"]($south,$west,$north,$east);
          );
        ''';
        break;

      case FishingLayerMode.allWaters:
      // “minden víz”, de csak poligon jelleg (stabil és gyors)
        body = '''
          (
            nwr["natural"="water"]($south,$west,$north,$east);
            nwr["waterway"="riverbank"]($south,$west,$north,$east);
          );
        ''';
        break;
    }

    // qt gyorsít: out ... qt;
    return '''
[out:json][timeout:$timeoutSeconds];
$body
out center tags qt;
''';
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  String? _pickName(Map<String, dynamic> tags) {
    final hu = (tags['name:hu'] as String?)?.trim();
    if (hu != null && hu.isNotEmpty) return hu;

    final name = (tags['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;

    final alt = (tags['alt_name'] as String?)?.trim();
    if (alt != null && alt.isNotEmpty) return alt;

    return null;
  }

  String _fallbackName(Map<String, dynamic> tags, FishingLayerMode mode) {
    final isFishingPoi = (tags['leisure'] == 'fishing');
    final isWater = (tags['natural'] == 'water');
    final waterway = (tags['waterway'] as String?)?.trim();

    if (isFishingPoi) return 'Horgászhely';
    if (isWater) {
      if (mode == FishingLayerMode.fishableWaters) return 'Horgászvíz';
      if (mode == FishingLayerMode.allWaters) return 'Vízfelület';
      return 'Víz';
    }
    if (waterway == 'riverbank') return 'Folyó';
    return 'Hely';
  }

  bool _isUsefulWater(Map<String, dynamic> tags) {
    // allWaters módban natural=water + riverbank kell.
    final natural = (tags['natural'] as String?)?.toLowerCase().trim();
    if (natural == 'water') return true;

    final waterway = (tags['waterway'] as String?)?.toLowerCase().trim();
    if (waterway == 'riverbank') return true;

    return false;
  }

  List<_Tile> _splitBbox(double s, double w, double n, double e, int nTiles) {
    final tiles = <_Tile>[];
    final dLat = (n - s) / nTiles;
    final dLon = (e - w) / nTiles;

    for (int i = 0; i < nTiles; i++) {
      for (int j = 0; j < nTiles; j++) {
        final ts = s + i * dLat;
        final tn = (i == nTiles - 1) ? n : (s + (i + 1) * dLat);
        final tw = w + j * dLon;
        final te = (j == nTiles - 1) ? e : (w + (j + 1) * dLon);

        tiles.add(_Tile(south: ts, west: tw, north: tn, east: te));
      }
    }
    return tiles;
  }
}

class _Tile {
  final double south;
  final double west;
  final double north;
  final double east;

  _Tile({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}
