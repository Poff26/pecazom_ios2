import 'ai_response.dart';
import 'weather_response.dart';

class WeatherForecastResponse {
  final WeatherResponse weather;
  final AIResponse ai;

  /// Backend quota: meta.plan
  final Map<String, dynamic>? plan;

  WeatherForecastResponse({
    required this.weather,
    required this.ai,
    this.plan,
  });

  factory WeatherForecastResponse.fromJson(Map<String, dynamic> json) {
    final weatherJson = json['weather'];
    if (weatherJson is! Map<String, dynamic>) {
      throw const FormatException('Missing weather object');
    }

    Map<String, dynamic>? plan;
    final meta = json['meta'];
    if (meta is Map<String, dynamic> && meta['plan'] is Map<String, dynamic>) {
      plan = Map<String, dynamic>.from(meta['plan']);
    }

    return WeatherForecastResponse(
      weather: WeatherResponse.fromJson(weatherJson),
      ai: AIResponse.fromJson(json),
      plan: plan,
    );
  }
}
