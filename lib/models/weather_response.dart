// lib/models/weather_response.dart
class WeatherResponse {
  final Location location;
  final Current current;
  final Forecast forecast;

  const WeatherResponse({
    required this.location,
    required this.current,
    required this.forecast,
  });

  factory WeatherResponse.fromJson(Map<String, dynamic> json) {
    // A backend sokszor WeatherAPI-s struktúrát ad:
    // { location: {...}, current: {...}, forecast: { forecastday: [...] } }
    return WeatherResponse(
      location: Location.fromJson(_asMap(json['location'])),
      current: Current.fromJson(_asMap(json['current'])),
      forecast: Forecast.fromJson(_asMap(json['forecast'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'location': location.toJson(),
    'current': current.toJson(),
    'forecast': forecast.toJson(),
  };
}

class Location {
  final String name;
  final String region;
  final String country;
  final double lat;
  final double lon;

  const Location({
    required this.name,
    required this.region,
    required this.country,
    required this.lat,
    required this.lon,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      name: (json['name'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      lat: _toDouble(json['lat']),
      lon: _toDouble(json['lon']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'region': region,
    'country': country,
    'lat': lat,
    'lon': lon,
  };
}

class Current {
  final double tempC;
  final double pressureMb;
  final double windKph;
  final int humidity;

  const Current({
    required this.tempC,
    required this.pressureMb,
    required this.windKph,
    required this.humidity,
  });

  factory Current.fromJson(Map<String, dynamic> json) {
    return Current(
      tempC: _toDouble(json['temp_c']),
      pressureMb: _toDouble(json['pressure_mb']),
      windKph: _toDouble(json['wind_kph']),
      humidity: _toInt(json['humidity']),
    );
  }

  Map<String, dynamic> toJson() => {
    'temp_c': tempC,
    'pressure_mb': pressureMb,
    'wind_kph': windKph,
    'humidity': humidity,
  };
}

class Forecast {
  final List<ForecastDay> forecastday;

  const Forecast({required this.forecastday});

  factory Forecast.fromJson(Map<String, dynamic> json) {
    final list = json['forecastday'];
    if (list is List) {
      return Forecast(
        forecastday: list
            .whereType<Map>()
            .map((e) => ForecastDay.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    return const Forecast(forecastday: []);
  }

  Map<String, dynamic> toJson() => {
    'forecastday': forecastday.map((e) => e.toJson()).toList(),
  };
}

class ForecastDay {
  final String date;
  final List<Hour> hour;

  const ForecastDay({
    required this.date,
    required this.hour,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> json) {
    final hours = json['hour'];
    return ForecastDay(
      date: (json['date'] ?? '').toString(),
      hour: (hours is List)
          ? hours
          .whereType<Map>()
          .map((e) => Hour.fromJson(Map<String, dynamic>.from(e)))
          .toList()
          : <Hour>[],
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'hour': hour.map((e) => e.toJson()).toList(),
  };
}

class Hour {
  final String time; // pl. "2026-01-06 12:00"
  final double tempC;
  final double pressureMb;
  final int chanceOfRain;

  const Hour({
    required this.time,
    required this.tempC,
    required this.pressureMb,
    required this.chanceOfRain,
  });

  factory Hour.fromJson(Map<String, dynamic> json) {
    // WeatherAPI tipikusan: chance_of_rain, temp_c, pressure_mb
    return Hour(
      time: (json['time'] ?? '').toString(),
      tempC: _toDouble(json['temp_c']),
      pressureMb: _toDouble(json['pressure_mb']),
      chanceOfRain: _toInt(json['chance_of_rain']),
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'temp_c': tempC,
    'pressure_mb': pressureMb,
    'chance_of_rain': chanceOfRain,
  };
}

/// --------- helpers (private) ---------

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const <String, dynamic>{};
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
