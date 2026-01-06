class FishingPin {
  final String id;
  final double lat;
  final double lon;
  final String name;
  final double fishWeight;
  final String fishSpecies;
  final double fishSize;
  final String pinColor;
  final String? imageUrl;
  final String userId;
  final String? bait;

  FishingPin({
    required this.id,
    required this.lat,
    required this.lon,
    required this.name,
    required this.fishWeight,
    required this.fishSpecies,
    required this.fishSize,
    required this.pinColor,
    required this.userId,
    this.imageUrl,
    this.bait,
  });

  factory FishingPin.fromJson(Map<String, dynamic> json) => FishingPin(
    id: (json['id'] ?? '').toString(),
    lat: _toDouble(json['lat']),
    lon: _toDouble(json['lon']),
    name: (json['name'] as String?)?.isNotEmpty == true
        ? json['name']
        : 'Névtelen hely',
    fishWeight: _toDouble(json['fishWeight']),
    fishSpecies: (json['fishSpecies'] as String?) ?? '',
    fishSize: _toDouble(json['fishSize']),
    pinColor: _safePinColor(json['pinColor']),
    imageUrl: (json['imageUrl'] as String?)?.isNotEmpty == true
        ? json['imageUrl']
        : null,
    userId: (json['userId'] as String?) ?? '',
    bait: (json['bait'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': lat,
    'lon': lon,
    'name': name,
    'fishWeight': fishWeight,
    'fishSpecies': fishSpecies,
    'fishSize': fishSize,
    'pinColor': pinColor,
    'imageUrl': imageUrl,
    'userId': userId,
    'bait': bait,
  };

  // --- Segédfüggvények ---
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static String _safePinColor(dynamic color) {
    if (color == null) return '#00FF00'; // Alapértelmezett zöld
    final String col = color.toString();
    final String hex = col.startsWith('#') ? col : '#$col';
    // Hex hossz ellenőrzés
    if (hex.length != 7) return '#00FF00';
    final valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex);
    return valid ? hex : '#00FF00';
  }
}
