import 'package:flutter/material.dart';
import 'package:fishing_app_flutter/widgets/weather/meteo_field_loader.dart';


class WeatherViewModel extends ChangeNotifier {
  final WeatherService _weatherService = WeatherService();

  WeatherResponse? weather;
  bool isLoading = false;
  String error = '';

  Future<void> loadWeather(double lat, double lon) async {
    isLoading = true;
    notifyListeners();

    try {
      weather = await _weatherService.fetchCurrentWeather(lat: lat, lon: lon);
      error = '';
    } catch (e) {
      error = e.toString();
    }

    isLoading = false;
    notifyListeners();
  }
}
