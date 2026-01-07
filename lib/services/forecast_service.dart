import 'dart:convert';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/forecast_response.dart';
import '../widgets/weather/meteo_field_loader.dart';

class ForecastService {
  static const _baseUrl = 'https://catchsense-backend.onrender.com';

  Future<WeatherForecastResponse> fetchCatchForecast({
    required double lat,
    required double lon,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Bejelentkezés szükséges.');
    }

    final token = await user.getIdToken(true);

    final uri = Uri.parse('$_baseUrl/catch-forecast');
    log('POST $uri', name: 'ForecastService');

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'lat': lat,
        'lon': lon,
      }),
    );

    if (resp.statusCode == 429) {
      final msg = jsonDecode(resp.body)['detail'] ?? 'Napi limit elérve';
      throw Exception(msg);
    }

    if (resp.statusCode != 200) {
      throw Exception('Forecast error ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;

    // időjárás merge a UI miatt
    final weather = await WeatherService().fetchCurrentWeather(lat: lat, lon: lon);
    decoded['weather'] = weather.toJson();

    return WeatherForecastResponse.fromJson(decoded);
  }
}
