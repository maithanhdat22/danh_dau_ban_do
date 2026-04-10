import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_style_option.dart';
import '../models/place_marker.dart';
import '../services/location_service.dart';
import '../services/search_service.dart';

class MapWidget extends StatefulWidget {
  final String currentUsername;
  final ValueChanged<PlaceMarker> onPlaceSaved;

  const MapWidget({
    super.key,
    required this.currentUsername,
    required this.onPlaceSaved,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  final MapController mapController = MapController();
  final TextEditingController searchController = TextEditingController();
  final Distance distanceCalculator = const Distance();

  LatLng? currentLocation;
  final List<LatLng> routePoints = [];
  final List<Marker> savedMarkers = [];

  Timer? timer;
  double totalDistanceInMeters = 0;

  MapStyleOption selectedStyle = MapStylePresets.presets.first;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    timer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  String get _tileUrl {
    switch (selectedStyle.baseMapType) {
      case BaseMapType.osmStandard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case BaseMapType.openTopo:
        return 'https://tile.openmaps.fr/opentopomap/{z}/{x}/{y}.png';
    }
  }

  String get _attributionText {
    switch (selectedStyle.baseMapType) {
      case BaseMapType.osmStandard:
        return '© OpenStreetMap contributors';
      case BaseMapType.openTopo:
        return '© OpenTopoMap-R • © OpenStreetMap';
    }
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) return;

    final firstPoint = LatLng(pos.latitude, pos.longitude);

    setState(() {
      currentLocation = firstPoint;
      routePoints.add(firstPoint);
    });

    mapController.move(firstPoint, 16);
    _startTracking();
  }

  void _startTracking() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null) return;

      final newPoint = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;

      setState(() {
        if (currentLocation != null) {
          final segmentDistance = distanceCalculator.as(
            LengthUnit.Meter,
            currentLocation!,
            newPoint,
          );

          if (segmentDistance >= 2) {
            totalDistanceInMeters += segmentDistance;
            routePoints.add(newPoint);
          }
        } else {
          routePoints.add(newPoint);
        }

        currentLocation = newPoint;
      });
    });
  }

  void _saveCurrentLocation() {
    if (currentLocation == null) return;

    final point = currentLocation!;

    setState(() {
      savedMarkers.add(
        Marker(
          point: point,
          width: 46,
          height: 46,
          child: Icon(
            Icons.location_pin,
            color: selectedStyle.theme.savedMarkerColor,
            size: 38,
          ),
        ),
      );
    });

    widget.onPlaceSaved(
      PlaceMarker(
        title:
        'Vị trí đã lưu ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        latitude: point.latitude,
        longitude: point.longitude,
        createdAt: DateTime.now(),
        distanceAtSave: totalDistanceInMeters,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu vị trí hiện tại')),
    );
  }

  void _addMarkerFromSearch(LatLng pos, String title) {
    setState(() {
      savedMarkers.add(
        Marker(
          point: pos,
          width: 46,
          height: 46,
          child: Icon(
            Icons.location_pin,
            color: selectedStyle.theme.savedMarkerColor,
            size: 38,
          ),
        ),
      );
    });

    widget.onPlaceSaved(
      PlaceMarker(
        title: title,
        latitude: pos.latitude,
        longitude: pos.longitude,
        createdAt: DateTime.now(),
        distanceAtSave: totalDistanceInMeters,
      ),
    );
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    final result = await SearchService.searchPlace(query.trim());
    if (result == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy địa điểm')),
      );
      return;
    }

    final lat = double.tryParse(result['lat'].toString());
    final lon = double.tryParse(result['lon'].toString());

    if (lat == null || lon == null) return;

    final pos = LatLng(lat, lon);

    mapController.move(pos, 14);
    _addMarkerFromSearch(pos, query.trim());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã tìm thấy: ${query.trim()}')),
    );
  }

  void _showStylePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: MapStylePresets.presets.length,
            itemBuilder: (context, index) {
              final style = MapStylePresets.presets[index];
              final isSelected = style.name == selectedStyle.name;

              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.map_outlined,
                  color: isSelected ? Colors.green : null,
                ),
                title: Text(style.name),
                subtitle: Text(
                  'Nền map: ${style.baseMapType == BaseMapType.osmStandard ? 'OSM Standard' : 'OpenTopoMap'} | Theme: ${style.theme.name}',
                ),
                onTap: () {
                  setState(() {
                    selectedStyle = style;
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(String text, {IconData? icon}) {
    return Card(
      color: selectedStyle.theme.infoCardColor,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: selectedStyle.theme.infoTextColor),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selectedStyle.theme.infoTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentLocation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentMarker = Marker(
      point: currentLocation!,
      width: 50,
      height: 50,
      child: Icon(
        Icons.my_location,
        color: selectedStyle.theme.currentMarkerColor,
        size: 36,
      ),
    );

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: currentLocation!,
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.danh_dau_ban_do',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: routePoints,
                  strokeWidth: 6,
                  color: selectedStyle.theme.routeColor,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                currentMarker,
                ...savedMarkers,
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(_attributionText),
              ],
            ),
          ],
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm tỉnh/thành, địa điểm...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () => _searchLocation(searchController.text),
                        icon: const Icon(Icons.send),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onSubmitted: _searchLocation,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'Xin chào, ${widget.currentUsername}',
                        icon: Icons.person,
                      ),
                    ),
                  ],
                ),

                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'Đã đi: ${(totalDistanceInMeters / 1000).toStringAsFixed(2)} km',
                        icon: Icons.route,
                      ),
                    ),
                  ],
                ),

                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'Style hiện tại: ${selectedStyle.name}',
                        icon: Icons.palette,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        Positioned(
          right: 16,
          bottom: 164,
          child: FloatingActionButton(
            heroTag: 'style_btn',
            backgroundColor: selectedStyle.theme.fabColor,
            onPressed: _showStylePicker,
            child: const Icon(Icons.layers),
          ),
        ),

        Positioned(
          right: 16,
          bottom: 90,
          child: FloatingActionButton(
            heroTag: 'save_location_btn',
            backgroundColor: selectedStyle.theme.fabColor,
            onPressed: _saveCurrentLocation,
            child: const Icon(Icons.bookmark_add),
          ),
        ),

        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'my_location_btn',
            backgroundColor: selectedStyle.theme.fabColor,
            onPressed: () {
              if (currentLocation != null) {
                mapController.move(currentLocation!, 16);
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}