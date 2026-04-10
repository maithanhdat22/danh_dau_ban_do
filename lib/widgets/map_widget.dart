import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/search_service.dart';

class MapWidget extends StatefulWidget {
  @override
  _MapWidgetState createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  LatLng? currentLocation;
  List<LatLng> route = [];
  List<Marker> markers = [];

  final MapController mapController = MapController();
  final TextEditingController searchController = TextEditingController();

  Timer? timer;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // 📍 Lấy vị trí ban đầu
  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) return;

    final latlng = LatLng(pos.latitude, pos.longitude);

    setState(() {
      currentLocation = latlng;

      markers.add(
        Marker(
          point: latlng,
          width: 40,
          height: 40,
          child: Icon(Icons.my_location, color: Colors.blue, size: 35),
        ),
      );
    });

    mapController.move(latlng, 15);
    _startTracking();
  }

  // 📈 Tracking
  void _startTracking() {
    timer = Timer.periodic(Duration(seconds: 10), (timer) async {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null) return;

      setState(() {
        route.add(LatLng(pos.latitude, pos.longitude));
      });
    });
  }

  // 📍 Click map
  void _addMarker(LatLng pos) {
    setState(() {
      markers.add(
        Marker(
          point: pos,
          width: 40,
          height: 40,
          child: Icon(Icons.location_pin, color: Colors.red),
        ),
      );
    });
  }

  // 🔍 Search
  void _searchLocation(String query) async {
    if (query.isEmpty) return;

    final result = await SearchService.searchPlace(query);
    if (result == null) return;

    final lat = double.parse(result["lat"]);
    final lon = double.parse(result["lon"]);

    final pos = LatLng(lat, lon);

    mapController.move(pos, 13);

    setState(() {
      markers.add(
        Marker(
          point: pos,
          width: 40,
          height: 40,
          child: Icon(Icons.location_pin, color: Colors.red),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentLocation == null) {
      return Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: currentLocation!,
            initialZoom: 15,
            onTap: (tapPosition, point) => _addMarker(point),
          ),
          children: [
            TileLayer(
              urlTemplate:
              "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
              subdomains: ['a', 'b', 'c'],
            ),

            MarkerLayer(markers: markers),

            PolylineLayer(
              polylines: [
                Polyline(
                  points: route,
                  strokeWidth: 4,
                  color: Colors.blue,
                ),
              ],
            ),
          ],
        ),

        // 🔍 Search box
        SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: "Tìm tỉnh/thành...",
                  border: InputBorder.none,
                  icon: Icon(Icons.search),
                ),
                onSubmitted: _searchLocation,
              ),
            ),
          ),
        ),
      ],
    );
  }
}