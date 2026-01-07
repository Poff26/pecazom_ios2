import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// =========================================================
/// 1) MODELS
/// =========================================================

class SamplePoint {
  final LatLng latLng;

  /// 0..1 normalizált érték
  final double value01;
  const SamplePoint(this.latLng, this.value01);
}

class SamplePointScreen {
  final Offset p;
  final double value01;
  const SamplePointScreen(this.p, this.value01);
}

/// =========================================================
/// 2) COLOR SCALE
/// =========================================================

Color heatColor(double t, {double alpha = 1.0}) {
  t = t.clamp(0.0, 1.0);

  Color lerp(Color a, Color b, double x) => Color.lerp(a, b, x)!;

  const c0 = Color(0xFF2A6FFF); // blue
  const c1 = Color(0xFF19C37D); // green
  const c2 = Color(0xFFFFC043); // yellow
  const c3 = Color(0xFFFF4D4D); // red

  final Color c;
  if (t < 0.33) {
    c = lerp(c0, c1, t / 0.33);
  } else if (t < 0.66) {
    c = lerp(c1, c2, (t - 0.33) / 0.33);
  } else {
    c = lerp(c2, c3, (t - 0.66) / 0.34);
  }

  return c.withOpacity(alpha);
}

/// =========================================================
/// 3) AUTO HEATMAP OVERLAY (NO TOGGLES)
/// - nincs "splat radius/intensity" UI kapcsoló
/// - a radius/intensity/grid automatikusan a zoom alapján
/// - óra "rendesen": alapból a mostani órát rajzolja (Local time)
/// - térkép mozgatásnál: debounce + cancel
/// =========================================================

typedef HeatFieldLoader = Future<List<SamplePoint>> Function({
required LatLngBounds bounds,
required int gridN,
required int hourIndex,
});

class AutoHeatmapOverlay extends StatefulWidget {
  /// GoogleMap controller kell a screen koordinátához.
  final GoogleMapController mapController;

  /// bounds+gridN+hourIndex alapján SamplePoint listát ad vissza.
  final HeatFieldLoader loadField;

  /// Helyi idő szerinti óra offset (pl. +3 = 3 óra múlva).
  final int hourOffset;

  /// Legend megjelenítés
  final bool showLegend;

  const AutoHeatmapOverlay({
    super.key,
    required this.mapController,
    required this.loadField,
    this.hourOffset = 0,
    this.showLegend = true,
  });

  @override
  State<AutoHeatmapOverlay> createState() => _AutoHeatmapOverlayState();
}

class _AutoHeatmapOverlayState extends State<AutoHeatmapOverlay> {
  List<SamplePointScreen> _screenPoints = const [];

  Timer? _debounce;
  int _jobId = 0; // cancel token
  double _lastZoom = -1;
  LatLngBounds? _lastBounds;

  // Cached paint params (auto)
  double _cachedRadiusPx = 46;
  double _cachedIntensity = 1.0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Hívd meg a GoogleMap-ből:
  /// - onCameraIdle: overlay.refreshFromMap()
  /// - onMapCreated után egyszer: overlay.refreshFromMap()
  Future<void> refreshFromMap() async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final int myJob = ++_jobId;

      // bounds + zoom
      final bounds = await widget.mapController.getVisibleRegion();
      final zoom = await widget.mapController.getZoomLevel();

      // Ha nagyon kicsi változás, ne tölts újra
      if (_lastBounds != null && _lastZoom >= 0) {
        final changed = _boundsChangedEnough(_lastBounds!, bounds) || (zoom - _lastZoom).abs() >= 0.35;
        if (!changed) return;
      }
      _lastBounds = bounds;
      _lastZoom = zoom;

      // Automatikus paraméterek
      final gridN = _autoGridN(zoom);
      final radiusPx = _autoRadiusPx(zoom);
      final intensity = _autoIntensity(zoom);

      // Óra: helyi idő szerinti óra index (0..23) + offset
      final now = DateTime.now().toLocal();
      final hourIndex = ((now.hour + widget.hourOffset) % 24);

      // Mezőpontok betöltése
      final pts = await widget.loadField(bounds: bounds, gridN: gridN, hourIndex: hourIndex);

      if (!mounted || myJob != _jobId) return;

      // FONTOS: Androidon a getScreenCoordinate gyakran fizikai px-ben jön.
      // Flutter Canvas logikai px-ben rajzol -> osztani kell devicePixelRatio-val.
      final dpr = MediaQuery.of(context).devicePixelRatio;

      final screen = <SamplePointScreen>[];
      for (final p in pts) {
        final sc = await widget.mapController.getScreenCoordinate(p.latLng);

        final dx = sc.x.toDouble() / dpr;
        final dy = sc.y.toDouble() / dpr;

        // védelem: NaN/Inf vagy extrém koordináta esetén eldobjuk
        if (!dx.isFinite || !dy.isFinite) continue;
        if (dx.abs() > 100000 || dy.abs() > 100000) continue;

        screen.add(SamplePointScreen(Offset(dx, dy), p.value01));
      }

      if (!mounted || myJob != _jobId) return;

      setState(() {
        _screenPoints = screen;
        _cachedRadiusPx = radiusPx;
        _cachedIntensity = intensity;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_screenPoints.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _HeatmapPainter(
              points: _screenPoints,
              radiusPx: _cachedRadiusPx,
              intensity: _cachedIntensity,
            ),
            child: widget.showLegend ? const _Legend() : null,
          ),
        ),
      ),
    );
  }

  // ------- AUTO TUNING -------

  int _autoGridN(double zoom) {
    if (zoom < 9.5) return 4; // 16 pont
    if (zoom < 11.0) return 5; // 25 pont
    if (zoom < 12.5) return 6; // 36 pont
    if (zoom < 14.0) return 7; // 49 pont
    return 8; // 64 pont
  }

  double _autoRadiusPx(double zoom) {
    final t = ((zoom - 9.5) / (14.0 - 9.5)).clamp(0.0, 1.0);
    return ui.lerpDouble(70, 34, t)!.clamp(18.0, 90.0);
  }

  double _autoIntensity(double zoom) {
    final t = ((zoom - 9.5) / (14.0 - 9.5)).clamp(0.0, 1.0);
    return ui.lerpDouble(1.15, 0.95, t)!.clamp(0.8, 1.3);
  }

  bool _boundsChangedEnough(LatLngBounds a, LatLngBounds b) {
    LatLng center(LatLngBounds x) => LatLng(
      (x.northeast.latitude + x.southwest.latitude) / 2.0,
      (x.northeast.longitude + x.southwest.longitude) / 2.0,
    );

    final ca = center(a);
    final cb = center(b);

    final dLat = (ca.latitude - cb.latitude).abs();
    final dLon = (ca.longitude - cb.longitude).abs();

    return dLat > 0.01 || dLon > 0.01;
  }
}

/// =========================================================
/// 4) OPTIMIZED PAINTER (FAST)
/// =========================================================

class _HeatmapPainter extends CustomPainter {
  final List<SamplePointScreen> points;
  final double radiusPx;
  final double intensity;

  _HeatmapPainter({
    required this.points,
    required this.radiusPx,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final r = radiusPx.clamp(10.0, 110.0);
    final k = intensity.clamp(0.0, 1.6);

    final paint = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.plus;

    final cull = Rect.fromLTWH(-r, -r, size.width + 2 * r, size.height + 2 * r);

    for (final sp in points) {
      if (!cull.contains(sp.p)) continue;

      final v = (sp.value01 * k).clamp(0.0, 1.0);

      final base = heatColor(v, alpha: (0.12 + 0.22 * v).clamp(0.0, 0.42));

      paint.shader = ui.Gradient.radial(
        sp.p,
        r,
        [
          base,
          base.withOpacity(base.opacity * 0.45),
          base.withOpacity(0.0),
        ],
        const [0.0, 0.55, 1.0],
      );

      canvas.drawCircle(sp.p, r, paint);
    }

    paint.shader = null;
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) {
    return old.points != points || old.radiusPx != radiusPx || old.intensity != intensity;
  }
}

/// =========================================================
/// 5) LEGEND
/// =========================================================

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendBar(),
                SizedBox(width: 10),
                Text(
                  'Alacsony → Magas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 10,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A6FFF),
            Color(0xFF19C37D),
            Color(0xFFFFC043),
            Color(0xFFFF4D4D),
          ],
        ),
      ),
    );
  }
}
