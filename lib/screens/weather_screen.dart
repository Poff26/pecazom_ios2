// lib/screens/weather_screen.dart
//
// Egyetlen fájlba rendezve (FRISSÍTVE):
// - WeatherService (WeatherAPI.com) + település-keresés (fetchWeatherByQuery)
// - Modellek (WeatherResponse + almodellek, toJson)
// - getCurrentLocation()
// - WeatherViewModel (60 perces SharedPreferences cache) + cacheKey GPS/település szerint
// - WeatherScreen: kereső településre (város alapján frissít)
// - Heatmap / meteo térkép: IDEIGLENESEN KIVÉVE A MEGJELENÍTÉSBŐL (UI-ból)
//
// Fontos: add a pubspec.yaml-hoz:
//   google_maps_flutter, geolocator, http, provider, fl_chart, shared_preferences
//
// Megjegyzés: A WeatherAPI kulcsot változatlanul hagytam.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Service: WeatherService
/// ─────────────────────────────────────────────────────────────────────────────
class WeatherService {
  static const String _apiKey = '683c54e2bff5444aaa6203219252703';
  static const String _baseUrl = 'https://api.weatherapi.com/v1/forecast.json';

  Future<WeatherResponse> fetchCurrentWeather({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl?key=$_apiKey&q=$lat,$lon&days=3&aqi=no&alerts=no',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load weather data (${response.statusCode})');
    }

    final Map<String, dynamic> jsonMap = jsonDecode(response.body);
    return WeatherResponse.fromJson(jsonMap);
  }

  /// ÚJ: település / keresőkifejezés alapú lekérés
  /// Példák: "Budapest", "Jászberény", "Szeged", "Győr"
  Future<WeatherResponse> fetchWeatherByQuery({
    required String query,
  }) async {
    final q = Uri.encodeComponent(query.trim());
    final uri = Uri.parse(
      '$_baseUrl?key=$_apiKey&q=$q&days=3&aqi=no&alerts=no',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Nem található település / hiba (${response.statusCode})');
    }

    final Map<String, dynamic> jsonMap = jsonDecode(response.body);
    return WeatherResponse.fromJson(jsonMap);
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Util: getCurrentLocation
/// ─────────────────────────────────────────────────────────────────────────────
Future<Position?> getCurrentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) return null;

  return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Models: WeatherResponse + Dependencies (with toJson)
/// ─────────────────────────────────────────────────────────────────────────────

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
        name: (json['name'] ?? '') as String,
        region: (json['region'] ?? '') as String,
        country: (json['country'] ?? '') as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        tzId: (json['tz_id'] ?? '') as String,
        localtime: (json['localtime'] ?? '') as String,
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
    final cond = (json['condition'] as Map<String, dynamic>? ?? const {});
    final iconRaw = (cond['icon'] ?? '') as String;
    return CurrentWeather(
      lastUpdated: (json['last_updated'] ?? '') as String,
      tempC: (json['temp_c'] as num).toDouble(),
      feelslikeC: (json['feelslike_c'] as num).toDouble(),
      humidity: (json['humidity'] as num).toInt(),
      windKph: (json['wind_kph'] as num).toDouble(),
      windDir: (json['wind_dir'] ?? '') as String,
      pressureMb: (json['pressure_mb'] as num).toDouble(),
      visKm: (json['vis_km'] as num).toDouble(),
      precipMm: (json['precip_mm'] as num).toDouble(),
      uv: (json['uv'] as num).toDouble(),
      conditionText: (cond['text'] ?? '') as String,
      iconUrl: iconRaw.startsWith('http') ? iconRaw : 'https:$iconRaw',
    );
  }

  Map<String, dynamic> toJson() => {
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
          'icon': iconUrl.replaceFirst('https:', ''),
        },
      };
}

class ForecastData {
  final List<ForecastDay> forecastday;

  ForecastData({required this.forecastday});

  factory ForecastData.fromJson(Map<String, dynamic> json) {
    final raw = (json['forecastday'] as List<dynamic>? ?? const []);
    return ForecastData(
      forecastday: raw.map((e) => ForecastDay.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'forecastday': forecastday.map((d) => d.toJson()).toList(),
      };
}

class AstroData {
  final String sunrise;
  final String sunset;

  AstroData({required this.sunrise, required this.sunset});

  factory AstroData.fromJson(Map<String, dynamic> json) => AstroData(
        sunrise: (json['sunrise'] ?? '') as String,
        sunset: (json['sunset'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {'sunrise': sunrise, 'sunset': sunset};
}

class HourData {
  final String time;
  final double tempC;
  final String conditionIcon; // raw icon path (usually starts with //cdn...)
  final int humidity;
  final int chanceOfRain;
  final double pressureMb;
  final double windKph;
  final String windDir;

  HourData({
    required this.time,
    required this.tempC,
    required this.conditionIcon,
    required this.humidity,
    required this.chanceOfRain,
    required this.pressureMb,
    required this.windKph,
    required this.windDir,
  });

  factory HourData.fromJson(Map<String, dynamic> json) {
    final cond = (json['condition'] as Map<String, dynamic>? ?? const {});
    return HourData(
      time: (json['time'] ?? '') as String,
      tempC: (json['temp_c'] as num).toDouble(),
      conditionIcon: (cond['icon'] ?? '') as String,
      humidity: (json['humidity'] as num).toInt(),
      chanceOfRain: (json['chance_of_rain'] as num?)?.toInt() ?? 0,
      pressureMb: (json['pressure_mb'] as num).toDouble(),
      windKph: (json['wind_kph'] as num?)?.toDouble() ?? 0,
      windDir: (json['wind_dir'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time,
        'temp_c': tempC,
        'condition': {'icon': conditionIcon},
        'humidity': humidity,
        'chance_of_rain': chanceOfRain,
        'pressure_mb': pressureMb,
        'wind_kph': windKph,
        'wind_dir': windDir,
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
    final cond = (json['condition'] as Map<String, dynamic>? ?? const {});
    return DayData(
      maxTempC: (json['maxtemp_c'] as num).toDouble(),
      minTempC: (json['mintemp_c'] as num).toDouble(),
      dailyChanceOfRain: (json['daily_chance_of_rain'] as num?)?.toInt() ?? 0,
      totalPrecipMm: (json['totalprecip_mm'] as num).toDouble(),
      uv: (json['uv'] as num).toDouble(),
      conditionText: (cond['text'] ?? '') as String,
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
        date: (json['date'] ?? '') as String,
        day: DayData.fromJson(json['day'] as Map<String, dynamic>),
        astro: AstroData.fromJson(json['astro'] as Map<String, dynamic>),
        hour: (json['hour'] as List<dynamic>? ?? const [])
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

/// ─────────────────────────────────────────────────────────────────────────────
/// ViewModel: 60 perces cache (SharedPreferences) – GPS és település szerint kulcsolva
/// ─────────────────────────────────────────────────────────────────────────────
class WeatherViewModel extends ChangeNotifier {
  final WeatherService _weatherService;

  WeatherResponse? weather;
  bool isLoading = false;
  String error = '';
  DateTime? lastLoadedAt;

  String activeQueryLabel = 'Helyalapú';

  WeatherViewModel({WeatherService? service}) : _weatherService = service ?? WeatherService();

  static const int _cacheMinutes = 60;

  Future<void> loadWeatherByGps(
    double lat,
    double lon, {
    bool force = false,
  }) async {
    final key = 'gps:${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    activeQueryLabel = 'Helyalapú';
    await _loadInternal(
      force: force,
      cacheKey: key,
      fetcher: () => _weatherService.fetchCurrentWeather(lat: lat, lon: lon),
    );
  }

  Future<void> loadWeatherByCity(
    String city, {
    bool force = false,
  }) async {
    final normalized = city.trim();
    final key = 'q:${normalized.toLowerCase()}';
    activeQueryLabel = normalized;
    await _loadInternal(
      force: force,
      cacheKey: key,
      fetcher: () => _weatherService.fetchWeatherByQuery(query: normalized),
    );
  }

  Future<void> _loadInternal({
    required bool force,
    required String cacheKey,
    required Future<WeatherResponse> Function() fetcher,
  }) async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      final lastUpdateString = prefs.getString('weather_last_update_$cacheKey');
      final weatherJsonString = prefs.getString('weather_data_$cacheKey');

      var shouldFetch = true;

      if (!force && lastUpdateString != null && weatherJsonString != null) {
        final lastUpdate = DateTime.tryParse(lastUpdateString);
        if (lastUpdate != null && now.difference(lastUpdate).inMinutes < _cacheMinutes) {
          final Map<String, dynamic> jsonMap = jsonDecode(weatherJsonString);
          weather = WeatherResponse.fromJson(jsonMap);
          shouldFetch = false;
        }
      }

      if (shouldFetch) {
        final fetched = await fetcher();
        weather = fetched;

        final encoded = jsonEncode(fetched.toJson());
        await prefs.setString('weather_data_$cacheKey', encoded);
        await prefs.setString('weather_last_update_$cacheKey', now.toIso8601String());
      }

      lastLoadedAt = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Kapási ablak
/// ─────────────────────────────────────────────────────────────────────────────
class _FishingWindow {
  final int startIndex;
  final int endIndex; // inclusive
  final DateTime startTime;
  final DateTime endTime;
  final int score0to100;
  final List<String> reasons;

  const _FishingWindow({
    required this.startIndex,
    required this.endIndex,
    required this.startTime,
    required this.endTime,
    required this.score0to100,
    required this.reasons,
  });
}

/// ─────────────────────────────────────────────────────────────────────────────
/// WeatherScreen (Premium) – keresővel, heatmap UI nélkül
/// ─────────────────────────────────────────────────────────────────────────────
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> with TickerProviderStateMixin {
  final viewModel = WeatherViewModel();

  Timer? _refreshTimer;
  Timer? _timeoutTimer;
  bool _timedOut = false;

  // Scroll-driven parallax
  final ValueNotifier<double> _scrollY = ValueNotifier<double>(0);

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _fadeCtrl,
    curve: Curves.easeOutCubic,
  );

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  // KERESŐ
  final TextEditingController _cityCtrl = TextEditingController();
  String? _lastCityQuery;

  @override
  void initState() {
    super.initState();
    _loadLocationAndWeather();
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) => _loadLocationAndWeather());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _timeoutTimer?.cancel();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _scrollY.dispose();
    _cityCtrl.dispose();
    viewModel.dispose();
    super.dispose();
  }

  Future<void> _loadLocationAndWeather() async {
    if (!mounted) return;

    setState(() => _timedOut = false);

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (viewModel.isLoading) setState(() => _timedOut = true);
    });

    final pos = await getCurrentLocation();
    if (!mounted) return;

    if (pos != null) {
      await viewModel.loadWeatherByGps(pos.latitude, pos.longitude, force: false);
    } else {
      viewModel
        ..error = 'Nem sikerült lekérni a helyadatokat.'
        ..isLoading = false;
      viewModel.notifyListeners();
    }
  }

  Future<void> _searchCityAndLoad(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    _lastCityQuery = q;
    await viewModel.loadWeatherByCity(q, force: true);
    if (mounted) FocusScope.of(context).unfocus();
  }

  // ----------------- Safe accessor -----------------
  double _hourTempC(HourData h) => h.tempC;
  double _hourPressureMb(HourData h) => h.pressureMb;
  double _hourWindKph(HourData h) => h.windKph;
  String _hourWindDir(HourData h) => h.windDir;
  int _hourHumidity(HourData h) => h.humidity;
  int _hourChanceOfRain(HourData h) => h.chanceOfRain;
  String _hourTime(HourData h) => h.time;

  // ----------------- Formatting helpers -----------------
  String _displayCity(String raw) {
    const overrides = {'Jaszbereny': 'Jászberény'};
    return overrides[raw] ?? raw;
  }

  String _translateCondition(String en) {
    const map = {
      'Sunny': 'Napos',
      'Clear': 'Derült',
      'Partly cloudy': 'Részben felhős',
      'Partly Cloudy': 'Részben felhős',
      'Cloudy': 'Felhős',
      'Overcast': 'Borult',
      'Mist': 'Párás',
      'Fog': 'Köd',
      'Freezing fog': 'Fagyos köd',
      'Patchy rain possible': 'Szórványos eső',
      'Light rain': 'Gyenge eső',
      'Moderate rain': 'Mérsékelt eső',
      'Heavy rain': 'Erős eső',
      'Light snow': 'Gyenge havazás',
      'Moderate snow': 'Közepes havazás',
      'Heavy snow': 'Erős havazás',
      'Thundery outbreaks possible': 'Zivatar lehetséges',
      'Moderate or heavy rain with thunder': 'Zivataros eső',
    };
    return map[en] ?? en;
  }

  String _displayWindDir(String dir) {
    const map = {'N': 'É', 'NE': 'ÉK', 'E': 'K', 'SE': 'DK', 'S': 'D', 'SW': 'DNY', 'W': 'NY', 'NW': 'ÉNY'};
    return map[dir] ?? dir;
  }

  String _weekdayHu(String date) {
    final weekDays = ['Hétfő', 'Kedd', 'Szerda', 'Csütörtök', 'Péntek', 'Szombat', 'Vasárnap'];
    final dt = DateTime.tryParse(date) ?? DateTime.now();
    return weekDays[dt.weekday - 1];
  }

  String _shortDate(String date) {
    final dt = DateTime.tryParse(date) ?? DateTime.now();
    return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  String _hhmmFromWeatherTime(String time) {
    final parts = time.split(' ');
    if (parts.length < 2) return time;
    final t = parts[1];
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  DateTime _parseHourDateTime(String time) {
    final s = time.replaceAll(' ', 'T');
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  // ----------------- Kapási ablak: scoring -----------------
  double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

  List<_FishingWindow> _computeBestFishingWindows(List<HourData> hours) {
    if (hours.length < 2) return const [];

    final candidates = <_FishingWindow>[];

    for (int i = 0; i < hours.length - 1; i++) {
      final h0 = hours[i];
      final h1 = hours[i + 1];

      final temp = (_hourTempC(h0) + _hourTempC(h1)) / 2.0;

      final p0 = _hourPressureMb(h0);
      final p1 = _hourPressureMb(h1);
      final pDeltaAbs = (p1 - p0).abs();

      final wind = (_hourWindKph(h0) + _hourWindKph(h1)) / 2.0;
      final rain = (_hourChanceOfRain(h0) + _hourChanceOfRain(h1)) / 2.0;
      final hum = (_hourHumidity(h0) + _hourHumidity(h1)) / 2.0;

      final pressureStability = _clamp01(1.0 - (pDeltaAbs / 3.0));

      double windScore;
      if (wind < 4) {
        windScore = wind / 4.0;
      } else if (wind <= 18) {
        windScore = 1.0;
      } else if (wind <= 32) {
        windScore = _clamp01(1.0 - ((wind - 18) / 14.0));
      } else {
        windScore = 0.0;
      }

      final rainScore = _clamp01(1.0 - (rain / 60.0));

      double tempScore;
      if (temp < 6) {
        tempScore = _clamp01(temp / 6.0);
      } else if (temp <= 24) {
        tempScore = 1.0;
      } else if (temp <= 32) {
        tempScore = _clamp01(1.0 - ((temp - 24) / 8.0));
      } else {
        tempScore = 0.0;
      }

      double humScore = 1.0;
      if (hum >= 90) {
        humScore = 0.75;
      } else if (hum >= 80) {
        humScore = 0.90;
      }

      final score01 = (0.34 * pressureStability) +
          (0.22 * windScore) +
          (0.22 * rainScore) +
          (0.16 * tempScore) +
          (0.06 * humScore);
      final score = (score01 * 100).round().clamp(0, 100);

      final reasons = <String>[];
      if (pressureStability >= 0.8) reasons.add('Stabil légnyomás');
      if (pDeltaAbs >= 2.0) reasons.add('Ingadozó légnyomás');
      if (windScore >= 0.9) reasons.add('Kedvező szél');
      if (wind >= 28) reasons.add('Erősebb szél');
      if (rain <= 20) reasons.add('Alacsony eső esély');
      if (rain >= 50) reasons.add('Nagyobb eső esély');
      if (temp >= 12 && temp <= 24) reasons.add('Kedvező hőmérséklet');
      if (hum >= 90) reasons.add('Magas páratartalom');

      final startT = _parseHourDateTime(_hourTime(h0));
      final endT = _parseHourDateTime(_hourTime(h1));

      candidates.add(
        _FishingWindow(
          startIndex: i,
          endIndex: i + 1,
          startTime: startT,
          endTime: endT,
          score0to100: score,
          reasons: reasons.take(3).toList(),
        ),
      );
    }

    candidates.sort((a, b) => b.score0to100.compareTo(a.score0to100));

    final picked = <_FishingWindow>[];
    for (final c in candidates) {
      final overlaps = picked.any((p) => !(c.endIndex < p.startIndex || c.startIndex > p.endIndex));
      if (!overlaps) {
        picked.add(c);
        if (picked.length == 3) break;
      }
    }

    if (picked.length < 3) {
      for (final c in candidates) {
        if (picked.contains(c)) continue;
        picked.add(c);
        if (picked.length == 3) break;
      }
    }

    return picked;
  }

  Color _scoreColor(ColorScheme scheme, int score) {
    if (score >= 75) return scheme.primary;
    if (score >= 55) return scheme.tertiary;
    return scheme.onSurfaceVariant;
  }

  String _windowLabel(_FishingWindow w) {
    String hhmm(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${hhmm(w.startTime)}–${hhmm(w.endTime)}';
  }

  bool _isNowInWindow(_FishingWindow w) {
    final now = DateTime.now();
    return now.isAfter(w.startTime) && now.isBefore(w.endTime);
  }

  // ----------------- UI constants -----------------
  static const _pagePad = EdgeInsets.fromLTRB(16, 12, 16, 18);

  // Glass tuning
  static const double _glassBlur = 10;
  static const double _glassOpacity = 0.72;
  static const double _glassBorderOpacity = 0.22;
  static const double _glassShadowOpacity = 0.10;

  // ----------------- Background (parallax gradient) -----------------
  Widget _parallaxBackground(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: _scrollY,
      builder: (context, y, _) {
        final offset = (y * 0.18).clamp(0.0, 180.0);

        return Stack(
          children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: scheme.surface))),
            Positioned(
              left: -120,
              right: -120,
              top: -160 + offset,
              height: 420,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withOpacity(0.20),
                        scheme.tertiary.withOpacity(0.14),
                        scheme.surface.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -140,
              right: -140,
              top: 280 + offset * 0.7,
              height: 520,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        scheme.secondary.withOpacity(0.10),
                        scheme.primary.withOpacity(0.06),
                        scheme.surface.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ----------------- Glass surface -----------------
  Widget _glassSurface(
    BuildContext context, {
    required Widget child,
    EdgeInsets? padding,
    BorderRadius? radius,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final r = radius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: _glassBlur, sigmaY: _glassBlur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(_glassOpacity),
            borderRadius: r,
            border: Border.all(color: scheme.outlineVariant.withOpacity(_glassBorderOpacity)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_glassShadowOpacity),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
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

  Widget _pill(BuildContext context, {required IconData icon, required String text}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return _glassSurface(
      context,
      padding: const EdgeInsets.all(14),
      radius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: t.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WeatherResponse w) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final last = viewModel.lastLoadedAt;
    final lastStr = last == null
        ? w.current.lastUpdated
        : '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withOpacity(0.26),
              scheme.tertiary.withOpacity(0.16),
              scheme.surface.withOpacity(0.58),
            ],
          ),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.50),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant.withOpacity(0.20)),
              ),
              child: const Icon(Icons.cloud_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayCity(w.location.name),
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(context, icon: Icons.schedule, text: 'Frissítve: $lastStr'),
                      _pill(context, icon: Icons.place_outlined, text: viewModel.activeQueryLabel),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Frissítés (force)',
              onPressed: () async {
                // Ha volt utolsó település-keresés, akkor azt frissítjük
                if ((_lastCityQuery ?? '').trim().isNotEmpty) {
                  await viewModel.loadWeatherByCity(_lastCityQuery!, force: true);
                  return;
                }

                // különben GPS
                final pos = await getCurrentLocation();
                if (pos != null) {
                  await viewModel.loadWeatherByGps(pos.latitude, pos.longitude, force: true);
                }
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _citySearchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _glassSurface(
      context,
      radius: BorderRadius.circular(22),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.search, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _cityCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Keress településre (pl. Budapest, Jászberény)',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(0.9)),
              ),
              onSubmitted: _searchCityAndLoad,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Keresés',
            onPressed: () => _searchCityAndLoad(_cityCtrl.text),
            icon: const Icon(Icons.arrow_forward),
          ),
          IconButton(
            tooltip: 'Vissza helyalapúra',
            onPressed: () async {
              _lastCityQuery = null;
              final pos = await getCurrentLocation();
              if (pos != null) {
                await viewModel.loadWeatherByGps(pos.latitude, pos.longitude, force: true);
              }
            },
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // --- Hero kártya ---
  Widget _heroCurrent(BuildContext context, WeatherResponse w) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    int rainChance = 0;
    try {
      final hourly = w.forecast.forecastday.first.hour;
      if (hourly.isNotEmpty) {
        final now = DateTime.now();
        int bestIdx = 0;
        int bestDiff = 1 << 30;
        for (int i = 0; i < hourly.length; i++) {
          final dt = _parseHourDateTime(hourly[i].time);
          final diff = (dt.difference(now).inMinutes).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestIdx = i;
          }
        }
        rainChance = hourly[bestIdx].chanceOfRain;
      }
    } catch (_) {
      rainChance = (w.current.precipMm > 0 ? 60 : 20);
    }

    return _glassSurface(
      context,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      radius: BorderRadius.circular(26),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 72,
              height: 72,
              color: scheme.surfaceVariant.withOpacity(0.22),
              child: Center(
                child: Image.network(
                  w.current.iconUrl,
                  width: 56,
                  height: 56,
                  errorBuilder: (_, __, ___) => const Icon(Icons.cloud_outlined, size: 34),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${w.current.tempC.toStringAsFixed(0)}°C',
                  style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.6),
                ),
                const SizedBox(height: 6),
                Text(
                  _translateCondition(w.current.conditionText),
                  style: t.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(context, icon: Icons.thermostat_outlined, text: 'Érzet: ${w.current.feelslikeC.toStringAsFixed(0)}°C'),
                    _pill(context, icon: Icons.air, text: 'Szél: ${w.current.windKph.toStringAsFixed(0)} km/h'),
                    _pill(context, icon: Icons.umbrella_outlined, text: 'Eső: $rainChance%'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- Loading/empty/error -----------------
  Widget _skeleton(BuildContext context) {
    Widget bar({double? w, double h = 14}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        );

    Widget card({double h = 110}) => _glassSurface(
          context,
          padding: const EdgeInsets.all(16),
          radius: BorderRadius.circular(24),
          child: SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(w: 160),
                const SizedBox(height: 10),
                bar(w: 220),
                const Spacer(),
                bar(w: 120),
              ],
            ),
          ),
        );

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _pagePad,
      child: Column(
        children: [
          card(h: 120),
          const SizedBox(height: 12),
          card(h: 120),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: card(h: 92)),
              const SizedBox(width: 10),
              Expanded(child: card(h: 92)),
            ],
          ),
          const SizedBox(height: 12),
          card(h: 220),
        ],
      ),
    );
  }

  Widget _errorState(BuildContext context, String error) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: scheme.error),
            const SizedBox(height: 10),
            Text('Hiba történt', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.25),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadLocationAndWeather,
              icon: const Icon(Icons.refresh),
              label: const Text('Újrapróbálás'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_outlined, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              _timedOut ? 'A betöltés túl sokáig tart.' : 'Nincs időjárási adat.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _timedOut
                  ? 'Frissíts, vagy ellenőrizd a helyhozzáférést és az internetkapcsolatot.'
                  : 'Húzd le a frissítéshez, vagy nyomj frissítést.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.25),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _loadLocationAndWeather, icon: const Icon(Icons.refresh), label: const Text('Frissítés')),
          ],
        ),
      ),
    );
  }

  // ----------------- Kapási ablak UI -----------------
  Widget _fishingWindowsSection(BuildContext context, WeatherResponse w) {
    final scheme = Theme.of(context).colorScheme;
    final hours = w.forecast.forecastday.first.hour;
    final best = _computeBestFishingWindows(hours);

    if (best.isEmpty) {
      return _glassSurface(
        context,
        radius: BorderRadius.circular(26),
        child: Text(
          'Nincs elég óránkénti adat a “kapási ablak” számításához.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    Widget scoreChip(int score, {bool prominent = false}) {
      final c = _scoreColor(scheme, score);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.withOpacity(prominent ? 0.18 : 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withOpacity(prominent ? 0.45 : 0.35)),
        ),
        child: Text('$score/100', style: TextStyle(fontWeight: FontWeight.w900, color: c)),
      );
    }

    Widget nowBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.primary.withOpacity(0.35)),
        ),
        child: Text('Most', style: TextStyle(fontWeight: FontWeight.w900, color: scheme.primary)),
      );
    }

    Widget trendBar(int score, Color accent) {
      final v = (score / 100).clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(color: scheme.surfaceVariant.withOpacity(0.28)),
              FractionallySizedBox(widthFactor: v, child: Container(color: accent.withOpacity(0.55))),
            ],
          ),
        ),
      );
    }

    Widget top1Tag(Color accent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Text('Top 1', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
      );
    }

    Widget windowCard(_FishingWindow fw, int idx) {
      final accent = _scoreColor(scheme, fw.score0to100);
      final isNow = _isNowInWindow(fw);
      final isTop = idx == 0;

      return SizedBox(
        width: 288,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            final pulse = isTop ? (0.97 + _pulseCtrl.value * 0.03) : 1.0;
            final glow = isTop ? accent.withOpacity(0.10 + _pulseCtrl.value * 0.10) : Colors.transparent;

            return Transform.scale(
              scale: pulse,
              child: _glassSurface(
                context,
                radius: BorderRadius.circular(26),
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isTop ? [BoxShadow(color: glow, blurRadius: 24, offset: const Offset(0, 12))] : null,
                  ),
                  child: SizedBox.expand(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(child: Text('Kapási ablak', style: TextStyle(fontWeight: FontWeight.w900))),
                                    if (isTop) ...[
                                      top1Tag(accent),
                                      const SizedBox(width: 8),
                                    ],
                                    if (isNow) ...[
                                      nowBadge(),
                                      const SizedBox(width: 8),
                                    ],
                                    scoreChip(fw.score0to100, prominent: isTop),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _windowLabel(fw),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2, color: accent),
                                ),
                                const SizedBox(height: 10),
                                Text('Heurisztikus trend', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 6),
                                trendBar(fw.score0to100, accent),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: fw.reasons.take(3).map((r) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceVariant.withOpacity(0.26),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: scheme.outlineVariant.withOpacity(0.18)),
                                      ),
                                      child: Text(r, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showFishingWindowDetails(context, fw, hours),
                            child: const Text('Részletek'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _glassSurface(
          context,
          radius: BorderRadius.circular(26),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: scheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.insights_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Top 3 kétórás időablak a mai napból. Gyors döntéstámogatás, pontszámmal.',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.25, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: best.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => windowCard(best[i], i),
          ),
        ),
      ],
    );
  }

  void _showFishingWindowDetails(BuildContext context, _FishingWindow fw, List<HourData> hours) {
    final scheme = Theme.of(context).colorScheme;

    final h0 = hours[fw.startIndex];
    final h1 = hours[fw.endIndex];

    final p0 = _hourPressureMb(h0);
    final p1 = _hourPressureMb(h1);
    final pDelta = p1 - p0;

    final wind0 = _hourWindKph(h0);
    final wind1 = _hourWindKph(h1);

    final rain0 = _hourChanceOfRain(h0);
    final rain1 = _hourChanceOfRain(h1);

    final temp0 = _hourTempC(h0);
    final temp1 = _hourTempC(h1);

    final dir = _displayWindDir(_hourWindDir(h0));
    final accent = _scoreColor(scheme, fw.score0to100);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, sc) {
          return SingleChildScrollView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: scheme.outlineVariant.withOpacity(0.6), borderRadius: BorderRadius.circular(999)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('Kapási ablak részletek', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Text('${fw.score0to100}/100', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _windowLabel(fw),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
                const SizedBox(height: 14),
                _glassSurface(
                  context,
                  radius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Összetevők', style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onSurface)),
                      const SizedBox(height: 10),
                      Text('Hőmérséklet: ${temp0.toStringAsFixed(0)}°C → ${temp1.toStringAsFixed(0)}°C'),
                      Text(
                        'Légnyomás: ${p0.toStringAsFixed(0)} mb → ${p1.toStringAsFixed(0)} mb (${pDelta >= 0 ? '+' : ''}${pDelta.toStringAsFixed(1)} mb)',
                      ),
                      Text('Szél: ${wind0.toStringAsFixed(1)} → ${wind1.toStringAsFixed(1)} km/h ($dir)'),
                      Text('Eső esély: $rain0% → $rain1%'),
                      const SizedBox(height: 10),
                      Text(
                        'Megjegyzés: heurisztikus index a mai órákra. Nem garancia, viszont gyors döntéstámogatás.',
                        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ----------------- Build -----------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ChangeNotifierProvider<WeatherViewModel>.value(
      value: viewModel,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: Stack(
          children: [
            _parallaxBackground(context),
            SafeArea(
              child: Consumer<WeatherViewModel>(
                builder: (_, vm, __) {
                  if (vm.error.isNotEmpty) return _errorState(context, vm.error);

                  if (vm.weather == null) {
                    if (vm.isLoading && !_timedOut) {
                      return FadeTransition(opacity: _fade, child: _skeleton(context));
                    }
                    return _emptyState(context);
                  }

                  final w = vm.weather!;
                  final hourly = w.forecast.forecastday.first.hour;
                  final pressures = hourly.map((h) => h.pressureMb).toList();
                  final daily = w.forecast.forecastday;

                  return FadeTransition(
                    opacity: _fade,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.axis == Axis.vertical) _scrollY.value = n.metrics.pixels;
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: _loadLocationAndWeather,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: _pagePad,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(context, w),
                              const SizedBox(height: 12),
                              _citySearchBar(context),
                              const SizedBox(height: 12),

                              _sectionTitle(context, title: 'Aktuális állapot', subtitle: 'Gyors, jól olvasható összefoglaló.'),
                              _heroCurrent(context, w),

                              _sectionTitle(context, title: 'Kapási ablakok', subtitle: 'Top 3 kétórás időablak a mai napból, pontszámmal.'),
                              _fishingWindowsSection(context, w),

                              _sectionTitle(context, title: 'Részletek', subtitle: 'Kiemelt mérőszámok gyors áttekintéshez.'),
                              LayoutBuilder(
                                builder: (context, c) {
                                  final itemWidth = (c.maxWidth - 10) / 2;
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.water_drop_outlined, label: 'Páratartalom', value: '${w.current.humidity}%')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.air, label: 'Szél', value: '${w.current.windKph.toStringAsFixed(1)} km/h • ${_displayWindDir(w.current.windDir)}')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.thermostat_outlined, label: 'Hőérzet', value: '${w.current.feelslikeC.toStringAsFixed(1)}°C')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.speed, label: 'Légnyomás', value: '${w.current.pressureMb.toStringAsFixed(0)} mb')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.visibility_outlined, label: 'Látótávolság', value: '${w.current.visKm.toStringAsFixed(1)} km')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.grain, label: 'Csapadék', value: '${w.current.precipMm.toStringAsFixed(1)} mm')),
                                      SizedBox(width: itemWidth, child: _metricCard(context, icon: Icons.wb_sunny_outlined, label: 'UV-index', value: '${w.current.uv.toStringAsFixed(1)}')),
                                    ],
                                  );
                                },
                              ),

                              _sectionTitle(context, title: 'Óránkénti légnyomás', subtitle: 'Trend az aktuális nap óráiban.'),
                              _glassSurface(
                                context,
                                padding: const EdgeInsets.all(16),
                                radius: BorderRadius.circular(26),
                                child: HourlyPressureChart(data: pressures),
                              ),

                              _sectionTitle(context, title: 'Óránkénti előrejelzés', subtitle: 'Hőmérséklet, nyomás, eső esély és páratartalom.'),
                              SizedBox(
                                height: 170,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: hourly.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                                  itemBuilder: (c, i) {
                                    final h = hourly[i];
                                    final time = _hhmmFromWeatherTime(h.time);

                                    final rawIcon = h.conditionIcon;
                                    final hasIcon = rawIcon.trim().isNotEmpty;
                                    final iconUrl = hasIcon ? (rawIcon.startsWith('http') ? rawIcon : 'https:$rawIcon') : '';

                                    final temp = h.tempC.toStringAsFixed(0);
                                    final pr = h.pressureMb.toStringAsFixed(0);
                                    final rain = h.chanceOfRain;
                                    final hum = h.humidity;

                                    return SizedBox(
                                      width: 158,
                                      child: _glassSurface(
                                        context,
                                        padding: const EdgeInsets.all(14),
                                        radius: BorderRadius.circular(22),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(time, style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                if (hasIcon)
                                                  Image.network(
                                                    iconUrl,
                                                    width: 34,
                                                    height: 34,
                                                    errorBuilder: (_, __, ___) => const Icon(Icons.cloud_outlined, size: 28),
                                                  )
                                                else
                                                  const Icon(Icons.cloud_outlined, size: 28),
                                                const SizedBox(width: 10),
                                                Text('$temp°C', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text('Nyomás: $pr mb', style: TextStyle(color: scheme.onSurfaceVariant)),
                                            Text('Eső: $rain%', style: TextStyle(color: scheme.onSurfaceVariant)),
                                            Text('Pára: $hum%', style: TextStyle(color: scheme.onSurfaceVariant)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              _sectionTitle(context, title: 'Napi előrejelzés', subtitle: 'Átlag, nyomás és eső esély napokra bontva.'),
                              SizedBox(
                                height: 154,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: daily.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                                  itemBuilder: (c, i) {
                                    final d = daily[i];
                                    final avgTemp = ((d.day.maxTempC + d.day.minTempC) / 2).round();

                                    final midHour = d.hour.length > 12 ? d.hour[12] : d.hour.first;
                                    final today = DateTime.now();
                                    final dDate = DateTime.tryParse(d.date) ?? today;
                                    final isToday = dDate.year == today.year && dDate.month == today.month && dDate.day == today.day;

                                    final midPressure = midHour.pressureMb;

                                    return SizedBox(
                                      width: 182,
                                      child: _glassSurface(
                                        context,
                                        padding: const EdgeInsets.all(14),
                                        radius: BorderRadius.circular(22),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_weekdayHu(d.date), style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text(
                                              isToday ? 'Ma' : _shortDate(d.date),
                                              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: 12),
                                            Text('Átlag: $avgTemp°C', style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 6),
                                            Text('Nyomás: ${midPressure.toStringAsFixed(0)} mb', style: TextStyle(color: scheme.onSurfaceVariant)),
                                            Text('Eső esély: ${d.day.dailyChanceOfRain}%', style: TextStyle(color: scheme.onSurfaceVariant)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // ───────────────────────────────────────────────────────────
                              // METEO / HEATMAP: IDEIGLENESEN KIVÉVE A MEGJELENÍTÉSBŐL
                              // ───────────────────────────────────────────────────────────
                              // _sectionTitle(context, title: 'Meteo térkép', subtitle: 'Heatmap / pontfelhő + poligonok (frontok, zónák).'),
                              // _meteoMapSection(context, w),

                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Óránkénti légnyomás grafikon
/// ─────────────────────────────────────────────────────────────────────────────
class HourlyPressureChart extends StatelessWidget {
  final List<double> data;

  const HourlyPressureChart({super.key, required this.data});

  double _min(List<double> xs) => xs.reduce((a, b) => a < b ? a : b);
  double _max(List<double> xs) => xs.reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('Nincs elérhető adat')));
    }

    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final minY = _min(data) - 2;
    final maxY = _max(data) + 2;

    final range = (maxY - minY).abs();
    final step = range <= 6 ? 1.0 : (range <= 12 ? 2.0 : 4.0);

    return SizedBox(
      height: 210,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (data.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            horizontalInterval: step,
            verticalInterval: 4,
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(enabled: true, handleBuiltInTouches: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              dotData: const FlDotData(show: false),
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Óra', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
              ),
              axisNameSize: 20,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: 4,
                getTitlesWidget: (v, _) {
                  final h = v.toInt();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$h:00', style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('mb', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
              ),
              axisNameSize: 20,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: step,
                getTitlesWidget: (v, _) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      ),
    );
  }
}
