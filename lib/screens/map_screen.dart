// lib/screens/map_screen.dart
//
// Profi, gyors, offline-clusteres térkép:
// - a te JSON-odat használja: assets/horgaszvizek_flutter_ready.json
// - körös cluster számmal (mint a mintaképen)
// - zoomra szétesik
// - kereső
// - marker tap -> bottom sheet (kép + leírás)
// - nincs Overpass, nincs hálózati töltögetés
//
// Követelmény pubspec.yaml-ban:
// flutter:
//   assets:
//     - assets/horgaszvizek_flutter_ready.json
//     - assets/icons/water.png
//     - assets/kepek/

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluster/fluster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class WaterItem {
  final String id;
  final String name;
  final String location;
  final double lat;
  final double lon;
  final String description;
  final String image;

  const WaterItem({
    required this.id,
    required this.name,
    required this.location,
    required this.lat,
    required this.lon,
    required this.description,
    required this.image,
  });

  factory WaterItem.fromJson(Map<String, dynamic> j, int idx) {
    final name = (j['name'] ?? 'Víz').toString().trim();
    final lat = (j['lat'] as num).toDouble();
    final lon = (j['lon'] as num).toDouble();

    // Stabil id (nem random): ha nincs id mező, generálunk determinisztikusan.
    final id = (j['id'] != null && j['id'].toString().trim().isNotEmpty)
        ? j['id'].toString()
        : 'w_${idx}_${name.hashCode}_${(lat * 1e5).round()}_${(lon * 1e5).round()}';

    return WaterItem(
      id: id,
      name: name.isEmpty ? 'Víz' : name,
      location: (j['location'] ?? '').toString(),
      lat: lat,
      lon: lon,
      description: (j['description'] ?? '').toString(),
      image: (j['image'] ?? '').toString(),
    );
  }
}

class FlusterPoint extends Clusterable {
  final String id; // saját id a MarkerId-hez
  final String name;
  final LatLng position;
  final WaterItem? water; // cluster esetén null

  FlusterPoint({
    required this.id,
    required this.name,
    required this.position,
    required this.water,
    required bool isCluster,
    required int pointsSize,
  }) : super(
    latitude: position.latitude,
    longitude: position.longitude,
    isCluster: isCluster,
    pointsSize: pointsSize,
    markerId: id,
  );
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Assets a te screenshotod alapján
  static const String _pointsAsset = 'assets/horgaszvizek_flutter_ready.json';
  static const String _pointIconAsset = 'assets/icons/water.png';

  static const CameraPosition _initial = CameraPosition(
    target: LatLng(47.2, 19.2),
    zoom: 7,
  );

  GoogleMapController? _ctrl;

  bool _loading = true;
  String? _error;

  double _zoom = _initial.zoom;

  Fluster<FlusterPoint>? _fluster;
  Set<Marker> _markers = {};

  // UI
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _idleDebounce;

  // Icons
  BitmapDescriptor? _pointIcon;

  // Cluster icon cache
  final Map<int, BitmapDescriptor> _clusterIconCache = {};

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text);
      _rebuildMarkers(); // local, instant
    });

    _init();
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      // pont ikon
      try {
        _pointIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(56, 56)),
          _pointIconAsset,
        );
      } catch (_) {
        _pointIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }

      // pontok betöltése (offline)
      final raw = await rootBundle.loadString(_pointsAsset);
      final decoded = json.decode(raw);

      if (decoded is! List) {
        throw Exception('A JSON gyökérelemnek listának kell lennie.');
      }

      final waters = <WaterItem>[];
      for (int i = 0; i < decoded.length; i++) {
        final m = decoded[i] as Map<String, dynamic>;
        waters.add(WaterItem.fromJson(m, i));
      }

      final points = waters.map((w) {
        return FlusterPoint(
          id: w.id,
          name: w.name,
          position: LatLng(w.lat, w.lon),
          water: w,
          isCluster: false,
          pointsSize: 1,
        );
      }).toList();

      // Fluster clustering
      _fluster = Fluster<FlusterPoint>(
        minZoom: 0,
        maxZoom: 20,
        radius: 170, // nagyobb radius -> országos nézetben szépen összevon
        extent: 2048,
        nodeSize: 64,
        points: points,
        createCluster: (base, lat, lng) => FlusterPoint(
          id: 'cluster_${(lat ?? 0).toStringAsFixed(5)}_${(lng ?? 0).toStringAsFixed(5)}_${base?.pointsSize ?? 1}',
          name: 'Cluster',
          position: LatLng(lat ?? 0.0, lng ?? 0.0),
          water: null,
          isCluster: true,
          pointsSize: base?.pointsSize ?? 1,
        ),
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });

      await _rebuildMarkers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Nem sikerült betölteni: $e';
      });
    }
  }

  // ---- Search normalize (HU ékezetek) ----
  String _norm(String s) {
    final t = s.trim().toLowerCase();
    return t
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ő', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ű', 'u');
  }

  bool _matches(String name, String q) {
    final nq = _norm(q);
    if (nq.isEmpty) return true;
    final nn = _norm(name);
    final tokens = nq.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    for (final t in tokens) {
      if (!nn.contains(t)) return false;
    }
    return true;
  }

  // ---- Cluster icon (kör + szám) ----
  Future<BitmapDescriptor> _clusterIcon(int count) async {
    // cache bucketok, hogy ne gyártsunk 1000 féle képet
    int bucket;
    if (count >= 500) bucket = 500;
    else if (count >= 200) bucket = 200;
    else if (count >= 100) bucket = 100;
    else if (count >= 50) bucket = 50;
    else if (count >= 20) bucket = 20;
    else if (count >= 10) bucket = 10;
    else bucket = 5;

    final cached = _clusterIconCache[bucket];
    if (cached != null) return cached;

    const int size = 160;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    // színezés a mennyiség alapján (kék -> narancs -> zöld)
    final Color outer;
    final Color inner;
    if (count >= 50) {
      outer = const Color(0xFF2E7D32);
      inner = const Color(0xFF66BB6A);
    } else if (count >= 20) {
      outer = const Color(0xFFEF6C00);
      inner = const Color(0xFFFFA726);
    } else {
      outer = const Color(0xFF1565C0);
      inner = const Color(0xFF64B5F6);
    }

    // shadow
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.22)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14);
    canvas.drawCircle(center, 64, shadow);

    // outer ring
    final pOuter = Paint()..color = outer;
    canvas.drawCircle(center, 62, pOuter);

    // white ring
    final pWhite = Paint()..color = Colors.white;
    canvas.drawCircle(center, 50, pWhite);

    // inner fill
    final pInner = Paint()..color = inner;
    canvas.drawCircle(center, 44, pInner);

    // text formatting
    final text = count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}k' : count.toString();

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 42,
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final img = await recorder.endRecording().toImage(size, size);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bd!.buffer.asUint8List());

    _clusterIconCache[bucket] = icon;
    return icon;
  }

  // ---- Marker rebuild ----
  Future<void> _rebuildMarkers() async {
    final fl = _fluster;
    if (fl == null) return;

    final clusters = fl.clusters([-180, -85, 180, 85], _zoom.toInt());
    final q = _query;

    // párhuzamosan építjük, hogy gyors legyen
    final futures = clusters.map((p) async {
      // csak a sima pontokra szűrünk név alapján
      if (p.isCluster != true && !_matches(p.name, q)) return null;

      if (p.isCluster == true) {
        final count = p.pointsSize ?? 1;
        return Marker(
          markerId: MarkerId(p.id),
          position: p.position,
          icon: await _clusterIcon(count),
          consumeTapEvents: true,
          onTap: () async {
            final c = _ctrl;
            if (c == null) return;
            await c.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: p.position,
                  zoom: (_zoom + 2).clamp(3, 20),
                ),
              ),
            );
          },
        );
      } else {
        final w = p.water;
        return Marker(
          markerId: MarkerId(p.id),
          position: p.position,
          icon: _pointIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          consumeTapEvents: true,
          onTap: () {
            if (w != null) _showWaterSheet(w);
          },
        );
      }
    }).toList();

    final built = await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      _markers = built.whereType<Marker>().toSet();
    });
  }

  // ---- Bottom sheet ----
  void _showWaterSheet(WaterItem w) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.60,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, scrollCtrl) {
          return SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Text(
                  w.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                if (w.location.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    w.location,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (w.image.trim().isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      w.image,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        alignment: Alignment.center,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Text('Kép nem elérhető'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (w.description.trim().isNotEmpty) ...[
                  Text(w.description, style: const TextStyle(height: 1.25)),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Koordináta: ${w.lat.toStringAsFixed(5)}, ${w.lon.toStringAsFixed(5)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          final c = _ctrl;
                          if (c == null) return;
                          await c.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target: LatLng(w.lat, w.lon),
                                zoom: math.max(_zoom, 14),
                              ),
                            ),
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.center_focus_strong),
                        label: const Text('Odaugrás'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- UI ----
  Widget _searchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.88),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Keresés tavak / vizek között…',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.trim().isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchCtrl.clear();
                  FocusScope.of(context).unfocus();
                },
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context) {
    if (!_loading && _error == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          if (_loading) ...[
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Betöltés…', style: TextStyle(fontWeight: FontWeight.w700))),
          ] else ...[
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initial,
            onMapCreated: (c) {
              _ctrl = c;
              _rebuildMarkers();
            },
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            markers: _markers,
            onCameraMove: (pos) => _zoom = pos.zoom,
            onCameraIdle: () {
              _idleDebounce?.cancel();
              _idleDebounce = Timer(const Duration(milliseconds: 80), () {
                _rebuildMarkers();
              });
            },
          ),
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchBar(context),
                _statusPill(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
