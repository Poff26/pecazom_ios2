// lib/meteo_heatmap_bundle.dart
//
// Egy fájlban: AUTO heatmap overlay + WeatherAPI-s WeatherService + WeatherViewModel cache-sel
// NINCS slider/chip kapcsoló. OnCameraIdle + debounce frissítés.
// Használat a legvégén (példa).

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// 1) HEATMAP MODELS + COLOR SCALE
/// ============================================================================

class SamplePoint {
  final LatLng latLng;
  final double value01; // 0..1
  const SamplePoint(this.latLng, this.value01);
}

class SamplePointScreen {
  final Offset p;
  final double value01;
  const SamplePointScreen(this.p, this.value01);
}

typedef HeatFieldLoader = Future<List<SamplePoint>> Function({
required LatLngBounds bounds,
required int gridN,
required int hourIndex,
});

Color heatColor(double t, {double alpha = 1.0}) {
  t = t.clamp(0.0, 1.0);
  Color lerp(Color a, Color b, double x) => Color.lerp(a, b, x)!;

  const c0 = Color(0xFF2A6FFF);
  const c1 = Color(0xFF19C37D);
  const c2 = Color(0xFFFFC043);
  const c3 = Color(0xFFFF4D4D);

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

/// ============================================================================
/// 2) AUTO HEATMAP OVERLAY (NO TOGGLES)
/// - zoom alapján auto grid/radius/intensity
/// - csak onCameraIdle + debounce
/// - cancel token (jobId)
/// - DPR korrekció
/// ============================================================================

class AutoHeatmapOverlay extends StatefulWidget {
  final GoogleMapController mapController;
  final HeatFieldLoader loadField;

  /// +0 = mostani óra (helyi idő)
  final int hourOffset;

  /// legend megjelenítés
  final bool showLegend;

  /// ha túl távol vagy: overlay off
  final double minZoomToShow;

  const AutoHeatmapOverlay({
    super.key,
    required this.mapController,
    required this.loadField,
    this.hourOffset = 0,
    this.showLegend = true,
    this.minZoomToShow = 8.5,
  });

  @override
  State<AutoHeatmapOverlay> createState() => _AutoHeatmapOverlayState();
}

class _AutoHeatmapOverlayState extends State<AutoHeatmapOverlay> {
  List<SamplePointScreen> _screenPoints = const [];

  Timer? _debounce;
  int _jobId = 0;
  double _lastZoom = -1;
  LatLngBounds? _lastBounds;

  double _cachedRadiusPx = 46;
  double _cachedIntensity = 1.0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Hívd meg a Map-ből:
  /// - onCameraIdle: overlayKey.currentState?.refreshFromMap()
  /// - onMapCreated után egyszer: overlayKey.currentState?.refreshFromMap()
  Future<void> refreshFromMap() async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final int myJob = ++_jobId;

      final bounds = await widget.mapController.getVisibleRegion();
      final zoom = await widget.mapController.getZoomLevel();

      if (!mounted || myJob != _jobId) return;

      if (zoom < widget.minZoomToShow) {
        setState(() => _screenPoints = const []);
        return;
      }

      // kis változásnál ne töltögessen
      if (_lastBounds != null && _lastZoom >= 0) {
        final changed =
            _boundsChangedEnough(_lastBounds!, bounds) || (zoom - _lastZoom).abs() >= 0.35;
        if (!changed) return;
      }
      _lastBounds = bounds;
      _lastZoom = zoom;

      final gridN = _autoGridN(zoom);
      final radiusPx = _autoRadiusPx(zoom);
      final intensity = _autoIntensity(zoom);

      final now = DateTime.now().toLocal();
      final hourIndex = ((now.hour + widget.hourOffset) % 24);

      final pts = await widget.loadField(bounds: bounds, gridN: gridN, hourIndex: hourIndex);
      if (!mounted || myJob != _jobId) return;

      // DPR korrekció (Android getScreenCoordinate gyakran physical px)
      final dpr = MediaQuery.of(context).devicePixelRatio;

      // párhuzamos getScreenCoordinate (gyorsabb)
      final futures = pts.map((p) async {
        final sc = await widget.mapController.getScreenCoordinate(p.latLng);
        final dx = sc.x.toDouble() / dpr;
        final dy = sc.y.toDouble() / dpr;
        if (!dx.isFinite || !dy.isFinite) return null;
        if (dx.abs() > 100000 || dy.abs() > 100000) return null;
        return SamplePointScreen(Offset(dx, dy), p.value01);
      }).toList();

      final screenRaw = await Future.wait(futures);
      if (!mounted || myJob != _jobId) return;

      final screen = screenRaw.whereType<SamplePointScreen>().toList();

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

/// ============================================================================
/// 3) WEATHER SERVICE + MODELS + VIEWMODEL (CACHE 60 PERC)
/// - WeatherAPI.com forecast
/// - SharedPreferences cache
/// ============================================================================

class WeatherService {
  static const String _apiKey = '683c54e2bff5444aaa6203219252703';
  static const String _baseUrl = 'https://api.weatherapi.com/v1/forecast.json';

  Future<WeatherResponse> fetchCurrentWeather({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse('$_baseUrl?key=$_apiKey&q=$lat,$lon&days=3&aqi=no&alerts=no');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load weather data (${response.statusCode})');
    }
    final Map<String, dynamic> jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
    return WeatherResponse.fromJson(jsonMap);
  }
}

class WeatherViewModel extends ChangeNotifier {
  final WeatherService _weatherService = WeatherService();

  WeatherResponse? weather;
  bool isLoading = false;
  String error = '';

  /// 60 perces cache.
  /// force=true -> mindig frissít.
  Future<void> loadWeather(
      double lat,
      double lon, {
        bool force = false,
      }) async {
    isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      final lastUpdateString = prefs.getString('weather_last_update');
      final weatherJsonString = prefs.getString('weather_data');

      var shouldFetch = true;

      if (!force && lastUpdateString != null && weatherJsonString != null) {
        final lastUpdate = DateTime.tryParse(lastUpdateString);
        if (lastUpdate != null && now.difference(lastUpdate).inMinutes < 60) {
          final Map<String, dynamic> jsonMap = jsonDecode(weatherJsonString) as Map<String, dynamic>;
          weather = WeatherResponse.fromJson(jsonMap);
          shouldFetch = false;
        }
      }

      if (shouldFetch) {
        final fetched = await _weatherService.fetchCurrentWeather(lat: lat, lon: lon);
        weather = fetched;

        await prefs.setString('weather_data', jsonEncode(fetched.toJson()));
        await prefs.setString('weather_last_update', now.toIso8601String());
      }

      error = '';
    } catch (e) {
      error = e.toString();
    }

    isLoading = false;
    notifyListeners();
  }
}

/// ------------------
/// Weather models
/// ------------------

class WeatherResponse {
  final LocationData location;
  final CurrentWeather current;
  final ForecastData forecast;

  WeatherResponse({
    required this.location,
    required this.current,
    required this.forecast,
  });

  factory WeatherResponse.fromJson(Map<String, dynamic> json) {
    return WeatherResponse(
      location: LocationData.fromJson(json['location'] as Map<String, dynamic>),
      current: CurrentWeather.fromJson(json['current'] as Map<String, dynamic>),
      forecast: ForecastData.fromJson(json['forecast'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'location': location.toJson(),
    'current': current.toJson(),
    'forecast': forecast.toJson(),
  };
}

class LocationData {
  final String name;
  final String region;
  final String country;
  final double lat;
  final double lon;
  final String tzId;
  final String localtime;

  LocationData({
    required this.name,
    required this.region,
    required this.country,
    required this.lat,
    required this.lon,
    required this.tzId,
    required this.localtime,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    name: (json['name'] as String?) ?? '',
    region: (json['region'] as String?) ?? '',
    country: (json['country'] as String?) ?? '',
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    tzId: (json['tz_id'] as String?) ?? '',
    localtime: (json['localtime'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'region': region,
    'country': country,
    'lat': lat,
    'lon': lon,
    'tz_id': tzId,
    'localtime': localtime,
  };
}

class CurrentWeather {
  final String lastUpdated;
  final double tempC;
  final double feelslikeC;
  final int humidity;
  final double windKph;
  final String windDir;
  final double pressureMb;
  final double visKm;
  final double precipMm;
  final double uv;
  final String conditionText;
  final String iconUrl;

  CurrentWeather({
    required this.lastUpdated,
    required this.tempC,
    required this.feelslikeC,
    required this.humidity,
    required this.windKph,
    required this.windDir,
    required this.pressureMb,
    required this.visKm,
    required this.precipMm,
    required this.uv,
    required this.conditionText,
    required this.iconUrl,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    final cond = (json['condition'] as Map<String, dynamic>?) ?? const {};
    final icon = (cond['icon'] as String?) ?? '';
    return CurrentWeather(
      lastUpdated: (json['last_updated'] as String?) ?? '',
      tempC: (json['temp_c'] as num).toDouble(),
      feelslikeC: (json['feelslike_c'] as num).toDouble(),
      humidity: (json['humidity'] as num).toInt(),
      windKph: (json['wind_kph'] as num).toDouble(),
      windDir: (json['wind_dir'] as String?) ?? '',
      pressureMb: (json['pressure_mb'] as num).toDouble(),
      visKm: (json['vis_km'] as num).toDouble(),
      precipMm: (json['precip_mm'] as num).toDouble(),
      uv: (json['uv'] as num).toDouble(),
      conditionText: (cond['text'] as String?) ?? '',
      iconUrl: icon.startsWith('http') ? icon : 'https:$icon',
    );
  }

  Map<String, dynamic> toJson() {
    final icon = iconUrl.replaceFirst('https:', '');
    return {
      'last_updated': lastUpdated,
      'temp_c': tempC,
      'feelslike_c': feelslikeC,
      'humidity': humidity,
      'wind_kph': windKph,
      'wind_dir': windDir,
      'pressure_mb': pressureMb,
      'vis_km': visKm,
      'precip_mm': precipMm,
      'uv': uv,
      'condition': {
        'text': conditionText,
        'icon': icon,
      },
    };
  }
}

class ForecastData {
  final List<ForecastDay> forecastday;

  ForecastData({required this.forecastday});

  factory ForecastData.fromJson(Map<String, dynamic> json) {
    final list = (json['forecastday'] as List<dynamic>? ?? const []);
    return ForecastData(
      forecastday: list.map((e) => ForecastDay.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'forecastday': forecastday.map((d) => d.toJson()).toList(),
  };
}

class ForecastDay {
  final String date;
  final DayData day;
  final AstroData astro;
  final List<HourData> hour;

  ForecastDay({
    required this.date,
    required this.day,
    required this.astro,
    required this.hour,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> json) => ForecastDay(
    date: (json['date'] as String?) ?? '',
    day: DayData.fromJson(json['day'] as Map<String, dynamic>),
    astro: AstroData.fromJson(json['astro'] as Map<String, dynamic>),
    hour: ((json['hour'] as List<dynamic>? ?? const []))
        .map((e) => HourData.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'day': day.toJson(),
    'astro': astro.toJson(),
    'hour': hour.map((h) => h.toJson()).toList(),
  };
}

class AstroData {
  final String sunrise;
  final String sunset;

  AstroData({
    required this.sunrise,
    required this.sunset,
  });

  factory AstroData.fromJson(Map<String, dynamic> json) => AstroData(
    sunrise: (json['sunrise'] as String?) ?? '',
    sunset: (json['sunset'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'sunrise': sunrise,
    'sunset': sunset,
  };
}

class HourData {
  final String time;
  final double tempC;
  final String conditionIcon;
  final int humidity;
  final int chanceOfRain;
  final double pressureMb;

  HourData({
    required this.time,
    required this.tempC,
    required this.conditionIcon,
    required this.humidity,
    required this.chanceOfRain,
    required this.pressureMb,
  });

  factory HourData.fromJson(Map<String, dynamic> json) {
    final cond = (json['condition'] as Map<String, dynamic>?) ?? const {};
    return HourData(
      time: (json['time'] as String?) ?? '',
      tempC: (json['temp_c'] as num).toDouble(),
      conditionIcon: (cond['icon'] as String?) ?? '',
      humidity: (json['humidity'] as num).toInt(),
      chanceOfRain: (json['chance_of_rain'] as num?)?.toInt() ?? 0,
      pressureMb: (json['pressure_mb'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'temp_c': tempC,
    'condition': {'icon': conditionIcon},
    'humidity': humidity,
    'chance_of_rain': chanceOfRain,
    'pressure_mb': pressureMb,
  };
}

class DayData {
  final double maxTempC;
  final double minTempC;
  final int dailyChanceOfRain;
  final double totalPrecipMm;
  final double uv;
  final String conditionText;

  DayData({
    required this.maxTempC,
    required this.minTempC,
    required this.dailyChanceOfRain,
    required this.totalPrecipMm,
    required this.uv,
    required this.conditionText,
  });

  factory DayData.fromJson(Map<String, dynamic> json) {
    final cond = (json['condition'] as Map<String, dynamic>?) ?? const {};
    return DayData(
      maxTempC: (json['maxtemp_c'] as num).toDouble(),
      minTempC: (json['mintemp_c'] as num).toDouble(),
      dailyChanceOfRain: (json['daily_chance_of_rain'] as num?)?.toInt() ?? 0,
      totalPrecipMm: (json['totalprecip_mm'] as num).toDouble(),
      uv: (json['uv'] as num).toDouble(),
      conditionText: (cond['text'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'maxtemp_c': maxTempC,
    'mintemp_c': minTempC,
    'daily_chance_of_rain': dailyChanceOfRain,
    'totalprecip_mm': totalPrecipMm,
    'uv': uv,
    'condition': {'text': conditionText},
  };
}

/// ============================================================================
/// 4) (OPCIONÁLIS) segéd: rács pontok számítása bounds alapján
/// - Ha a saját API-d rácsot vár: ezt használd.
/// ============================================================================

List<LatLng> buildGridPoints(LatLngBounds bounds, int gridN) {
  final south = bounds.southwest.latitude;
  final north = bounds.northeast.latitude;
  final west = bounds.southwest.longitude;
  final east = bounds.northeast.longitude;

  // anti-meridian egyszerű kezelés: ha east < west, átváltunk 0..360 tartományra
  final bool wrap = east < west;
  double normLon(double lon) => (lon < 0) ? lon + 360.0 : lon;
  final w = wrap ? normLon(west) : west;
  final e = wrap ? normLon(east) : east;

  final pts = <LatLng>[];
  for (int iy = 0; iy < gridN; iy++) {
    final ty = gridN == 1 ? 0.5 : iy / (gridN - 1);
    final lat = south + (north - south) * ty;

    for (int ix = 0; ix < gridN; ix++) {
      final tx = gridN == 1 ? 0.5 : ix / (gridN - 1);
      final lonN = w + (e - w) * tx;
      final lon = wrap ? ((lonN > 180) ? lonN - 360.0 : lonN) : lonN;
      pts.add(LatLng(lat, lon));
    }
  }
  return pts;
}

/// ============================================================================
/// 5) GYORS PÉLDA HASZNÁLAT (csak illusztráció, nem kötelező)
/// ============================================================================
///
/// final overlayKey = GlobalKey<_AutoHeatmapOverlayState>();
///
/// Stack(
///   children: [
///     GoogleMap(
///       onMapCreated: (c) { _ctrl = c; overlayKey.currentState?.refreshFromMap(); },
///       onCameraIdle: () => overlayKey.currentState?.refreshFromMap(),
///     ),
///     AutoHeatmapOverlay(
///       key: overlayKey,
///       mapController: _ctrl!,
///       loadField: ({required bounds, required gridN, required hourIndex}) async {
///         // IDE jön a valós adat: API hívás, Firestore, stb.
///         // return List<SamplePoint>(...);
///         return const [];
///       },
///     ),
///   ],
/// )
///
