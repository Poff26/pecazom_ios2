import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fishing_app_flutter/models/weather_response.dart';

class WeatherService {
  // Backend base URL
  static const String _baseUrl = 'https://catchsense-backend.onrender.com';

  /// Backend expected: GET /weather?lat=..&lon=..
  /// Response: WeatherAPI-like JSON (location / current / forecast)
  Future<WeatherResponse> fetchCurrentWeather({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse('$_baseUrl/weather').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
    });

    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode != 200) {
      String detail = 'HTTP ${resp.statusCode}';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {}
      throw Exception('WeatherService error: $detail');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('WeatherService: invalid JSON object');
    }

    return WeatherResponse.fromJson(decoded);
  }
}
