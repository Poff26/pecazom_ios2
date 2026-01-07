// fishing_lakes_map.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FishingLake {
  final String name;
  final String location;
  final double lat;
  final double lon;

  FishingLake({
    required this.name,
    required this.location,
    required this.lat,
    required this.lon,
  });

  factory FishingLake.fromJson(Map<String, dynamic> json) {
    return FishingLake(
      name: json['name'],
      location: json['location'],
      lat: json['lat'],
      lon: json['lon'],
    );
  }
}

class FishingLakesMap extends StatefulWidget {
  const FishingLakesMap({super.key});

  @override
  State<FishingLakesMap> createState() => _FishingLakesMapState();
}

class _FishingLakesMapState extends State<FishingLakesMap> {
  final Set<Marker> _markers = {};
  late GoogleMapController _mapController;

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    final String data = await rootBundle.loadString('assets/horgaszvizek_geo.json');
    final List<dynamic> jsonList = json.decode(data);
    final lakes = jsonList.map((e) => FishingLake.fromJson(e)).toList();

    setState(() {
      _markers.addAll(lakes.map((lake) => Marker(
        markerId: MarkerId(lake.name),
        position: LatLng(lake.lat, lake.lon),
        infoWindow: InfoWindow(
          title: lake.name,
          snippet: lake.location,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      )));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Horgászvizek térképe')),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(47.0, 19.5),
          zoom: 7,
        ),
        markers: _markers,
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: true,
      ),
    );
  }
}
