import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/map_style_option.dart';
import '../models/place_marker.dart';
import '../models/transport_option.dart';
import '../services/location_service.dart';
import '../services/search_service.dart';

enum SearchMode {
  start,
  stop,
  destination,
}

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

  LatLng? startPoint;
  String startName = 'Vị trí hiện tại';

  final List<LatLng> stopPoints = [];
  final List<String> stopNames = [];

  LatLng? destinationPoint;
  String destinationName = '';

  List<LatLng> routedPath = [];

  double plannedRouteDistanceInMeters = 0;
  double plannedRouteDurationInSeconds = 0;
  double remainingDistanceInMeters = 0;
  double remainingDurationInSeconds = 0;

  bool isRouting = false;
  bool isNavigating = false;

  final List<Marker> savedMarkers = [];

  Timer? timer;
  double totalDistanceInMeters = 0;

  MapStyleOption selectedStyle = MapStylePresets.presets.first;
  TransportOption selectedTransport = TransportOptions.items.first;
  SearchMode currentSearchMode = SearchMode.destination;

  final List<String> recentSearches = [];
  bool showRecentSearches = false;
  bool isSearching = false;
  List<Map<String, dynamic>> searchSuggestions = [];
  bool showSuggestions = false;

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

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) return;

    final firstPoint = LatLng(pos.latitude, pos.longitude);

    if (!mounted) return;

    setState(() {
      currentLocation = firstPoint;
      routePoints.add(firstPoint);
      startPoint = firstPoint;
    });

    mapController.move(firstPoint, 15);
    _startTracking();
  }

  void _startTracking() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null) return;

      final newPoint = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;

      bool shouldReroute = false;

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

          if (isNavigating && segmentDistance >= 5) {
            shouldReroute = true;
          }
        }

        currentLocation = newPoint;
      });

      if (isNavigating) {
        if (currentLocation != null) {
          mapController.move(currentLocation!, 17);
        }

        if (shouldReroute) {
          await _buildNavigationRoute();
        }

        if (remainingDistanceInMeters > 0 && remainingDistanceInMeters <= 30) {
          if (!mounted) return;
          setState(() {
            isNavigating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bạn đã gần tới điểm đến')),
          );
        }
      }
    });
  }

  void _addRecentSearch(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;

    setState(() {
      recentSearches.remove(keyword);
      recentSearches.insert(0, keyword);

      if (recentSearches.length > 6) {
        recentSearches.removeLast();
      }
    });
  }

  void _hideSearchPanels() {
    if (!mounted) return;
    setState(() {
      showRecentSearches = false;
      showSuggestions = false;
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final keyword = query.trim();

    if (keyword.isEmpty) {
      if (!mounted) return;
      setState(() {
        searchSuggestions = [];
        showSuggestions = false;
        showRecentSearches = recentSearches.isNotEmpty;
        isSearching = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
      showRecentSearches = false;
    });

    final results = await SearchService.searchPlaces(keyword);

    if (!mounted) return;
    setState(() {
      searchSuggestions = results;
      showSuggestions = results.isNotEmpty;
      isSearching = false;
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> item) async {
    final lat = double.tryParse(item['lat'].toString());
    final lon = double.tryParse(item['lon'].toString());
    final displayName = (item['display_name'] ?? '').toString();

    if (lat == null || lon == null) return;

    final point = LatLng(lat, lon);
    final title = displayName.isNotEmpty ? displayName : 'Địa điểm đã chọn';

    _addRecentSearch(title);

    setState(() {
      switch (currentSearchMode) {
        case SearchMode.start:
          startPoint = point;
          startName = title;
          break;
        case SearchMode.stop:
          stopPoints.add(point);
          stopNames.add(title);
          break;
        case SearchMode.destination:
          destinationPoint = point;
          destinationName = title;
          break;
      }
      showSuggestions = false;
      showRecentSearches = false;
    });

    final previewPoints = _getPreviewWaypoints();
    if (previewPoints.length >= 2) {
      mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: previewPoints,
          padding: const EdgeInsets.all(80),
        ),
      );
    } else {
      mapController.move(point, 15);
    }

    await _buildPreviewRoute();

    if (!mounted) return;

    searchController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chọn: $title')),
    );

    setState(() {
      currentSearchMode = SearchMode.destination;
    });
  }

  void _selectRecentSearch(String value) {
    searchController.text = value;
    _searchLocation(value);
  }

  void _selectPointOnMap(LatLng point) {
    final title =
        'Lat ${point.latitude.toStringAsFixed(5)}, Lng ${point.longitude.toStringAsFixed(5)}';

    setState(() {
      switch (currentSearchMode) {
        case SearchMode.start:
          startPoint = point;
          startName = title;
          break;
        case SearchMode.stop:
          stopPoints.add(point);
          stopNames.add(title);
          break;
        case SearchMode.destination:
          destinationPoint = point;
          destinationName = title;
          break;
      }
      showRecentSearches = false;
      showSuggestions = false;
    });

    final previewPoints = _getPreviewWaypoints();
    if (previewPoints.length >= 2) {
      mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: previewPoints,
          padding: const EdgeInsets.all(80),
        ),
      );
    } else {
      mapController.move(point, 15);
    }

    _buildPreviewRoute();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chọn điểm: $title')),
    );
  }

  String _getOsrmProfile() {
    final name = selectedTransport.name.toLowerCase();
    if (name.contains('đi bộ')) return 'foot';
    if (name.contains('xe đạp')) return 'bike';
    return 'driving';
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0) return '0 phút';

    final totalMinutes = (seconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours == 0) return '$minutes phút';
    return '$hours giờ ${minutes.toString().padLeft(2, '0')} phút';
  }

  String _searchHintText() {
    switch (currentSearchMode) {
      case SearchMode.start:
        return 'Nhập điểm bắt đầu...';
      case SearchMode.stop:
        return 'Nhập điểm dừng...';
      case SearchMode.destination:
        return 'Nhập điểm đến...';
    }
  }

  List<LatLng> _getPreviewWaypoints() {
    final points = <LatLng>[];
    if (startPoint != null) points.add(startPoint!);
    points.addAll(stopPoints);
    if (destinationPoint != null) points.add(destinationPoint!);
    return points;
  }

  List<LatLng> _getNavigationWaypoints() {
    final points = <LatLng>[];
    if (currentLocation != null) {
      points.add(currentLocation!);
    } else if (startPoint != null) {
      points.add(startPoint!);
    }
    points.addAll(stopPoints);
    if (destinationPoint != null) points.add(destinationPoint!);
    return points;
  }

  Future<void> _requestRoute({
    required List<LatLng> waypoints,
    required bool forNavigation,
  }) async {
    if (waypoints.length < 2) {
      setState(() {
        routedPath = [];
        plannedRouteDistanceInMeters = 0;
        plannedRouteDurationInSeconds = 0;
        remainingDistanceInMeters = 0;
        remainingDurationInSeconds = 0;
      });
      return;
    }

    setState(() {
      isRouting = true;
    });

    try {
      final profile = _getOsrmProfile();
      final coordinates =
      waypoints.map((e) => '${e.longitude},${e.latitude}').join(';');

      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/$profile/$coordinates'
            '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('OSRM request failed');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        throw Exception('Route not found');
      }

      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw Exception('No route data');
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final geometry = firstRoute['geometry'] as Map<String, dynamic>;
      final coordinatesList = geometry['coordinates'] as List<dynamic>;

      final points = coordinatesList.map((item) {
        final pair = item as List<dynamic>;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        routedPath = points;
        plannedRouteDistanceInMeters =
            (firstRoute['distance'] as num).toDouble();
        plannedRouteDurationInSeconds =
            (firstRoute['duration'] as num).toDouble();

        if (forNavigation) {
          remainingDistanceInMeters = plannedRouteDistanceInMeters;
          remainingDurationInSeconds = plannedRouteDurationInSeconds;
        }

        isRouting = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isRouting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm được tuyến đường')),
      );
    }
  }

  Future<void> _buildPreviewRoute() async {
    await _requestRoute(
      waypoints: _getPreviewWaypoints(),
      forNavigation: false,
    );
  }

  Future<void> _buildNavigationRoute() async {
    await _requestRoute(
      waypoints: _getNavigationWaypoints(),
      forNavigation: true,
    );
  }

  Future<void> _searchLocation(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;

    _addRecentSearch(keyword);

    final result = await SearchService.searchPlace(keyword);

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

    final point = LatLng(lat, lon);
    final title = (result['display_name'] ?? keyword).toString();

    setState(() {
      switch (currentSearchMode) {
        case SearchMode.start:
          startPoint = point;
          startName = title;
          break;
        case SearchMode.stop:
          stopPoints.add(point);
          stopNames.add(title);
          break;
        case SearchMode.destination:
          destinationPoint = point;
          destinationName = title;
          break;
      }
      showRecentSearches = false;
      showSuggestions = false;
    });

    final previewPoints = _getPreviewWaypoints();
    if (previewPoints.length >= 2) {
      mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: previewPoints,
          padding: const EdgeInsets.all(80),
        ),
      );
    } else {
      mapController.move(point, 15);
    }

    await _buildPreviewRoute();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chọn: $title')),
    );

    searchController.clear();
    setState(() {
      currentSearchMode = SearchMode.destination;
    });
  }

  Future<void> _startNavigation() async {
    if (destinationPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy chọn điểm đến trước')),
      );
      return;
    }

    setState(() {
      isNavigating = true;
      showRecentSearches = false;
      showSuggestions = false;
    });

    await _buildNavigationRoute();

    if (!mounted) return;

    if (currentLocation != null) {
      mapController.move(currentLocation!, 17);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã bắt đầu chỉ đường')),
    );
  }

  void _stopNavigation() {
    setState(() {
      isNavigating = false;
      remainingDistanceInMeters = plannedRouteDistanceInMeters;
      remainingDurationInSeconds = plannedRouteDurationInSeconds;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã dừng chỉ đường')),
    );
  }

  void _removeLastStop() {
    if (stopPoints.isEmpty) return;

    setState(() {
      stopPoints.removeLast();
      stopNames.removeLast();
    });

    if (isNavigating) {
      _buildNavigationRoute();
    } else {
      _buildPreviewRoute();
    }
  }

  void _clearRoute() {
    setState(() {
      startPoint = currentLocation;
      startName = 'Vị trí hiện tại';
      stopPoints.clear();
      stopNames.clear();
      destinationPoint = null;
      destinationName = '';
      routedPath = [];
      plannedRouteDistanceInMeters = 0;
      plannedRouteDurationInSeconds = 0;
      remainingDistanceInMeters = 0;
      remainingDurationInSeconds = 0;
      isNavigating = false;
      currentSearchMode = SearchMode.destination;
      showRecentSearches = false;
      showSuggestions = false;
    });
  }

  String _buildStaticMapImage(LatLng point) {
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=${point.latitude},${point.longitude}&zoom=15&size=700x350&markers=${point.latitude},${point.longitude},red-pushpin';
  }

  String _buildAddressText(LatLng point) {
    return 'Lat: ${point.latitude.toStringAsFixed(6)}, Lng: ${point.longitude.toStringAsFixed(6)}';
  }

  void _saveCurrentLocation() {
    if (currentLocation == null) return;

    final point = currentLocation!;
    final now = DateTime.now();
    final imageUrl = _buildStaticMapImage(point);
    final address = _buildAddressText(point);

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
        id: now.millisecondsSinceEpoch.toString(),
        title: 'Vị trí ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        latitude: point.latitude,
        longitude: point.longitude,
        createdAt: now,
        distanceAtSave: totalDistanceInMeters,
        transportName: selectedTransport.name,
        description: 'Địa điểm đã đi qua và được lưu từ bản đồ',
        imageUrl: imageUrl,
        address: address,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu vị trí')),
    );
  }

  void _showTransportPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: TransportOptions.items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (_, i) {
            final t = TransportOptions.items[i];
            final isSelected = t.name == selectedTransport.name;

            return GestureDetector(
              onTap: () async {
                setState(() {
                  selectedTransport = t;
                });
                Navigator.pop(context);

                if (isNavigating) {
                  await _buildNavigationRoute();
                } else {
                  await _buildPreviewRoute();
                }
              },
              child: Card(
                color: isSelected ? Colors.orange.shade100 : null,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 6),
                      Text(
                        t.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showStylePicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return ListView.builder(
          itemCount: MapStylePresets.presets.length,
          itemBuilder: (_, i) {
            final style = MapStylePresets.presets[i];
            final isSelected = style.name == selectedStyle.name;

            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.map_outlined,
                color: isSelected ? Colors.green : null,
              ),
              title: Text(style.name),
              onTap: () {
                setState(() {
                  selectedStyle = style;
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _bottomButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.6 : 1,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: onPressed,
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required SearchMode mode,
  }) {
    final active = currentSearchMode == mode;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 46,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? const Color(0xFF2563EB) : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                currentSearchMode = mode;
                showRecentSearches = false;
                showSuggestions = false;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? Colors.white : const Color(0xFF1F2937),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuTile(String text, IconData icon) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _searchPanel() {
    if (showSuggestions && searchSuggestions.isNotEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: searchSuggestions.map((item) {
            final title = (item['display_name'] ?? 'Địa điểm').toString();
            return ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectSuggestion(item),
            );
          }).toList(),
        ),
      );
    }

    if (showRecentSearches && recentSearches.isNotEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: recentSearches.map((item) {
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectRecentSearch(item),
            );
          }).toList(),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showInfoMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                _menuTile('Người dùng: ${widget.currentUsername}', Icons.person),
                _menuTile('Bắt đầu: $startName', Icons.trip_origin),
                _menuTile(
                  'Điểm dừng: ${stopNames.isEmpty ? 'Chưa có' : stopNames.join(' → ')}',
                  Icons.add_location_alt,
                ),
                _menuTile(
                  'Điểm đến: ${destinationName.isEmpty ? 'Chưa chọn' : destinationName}',
                  Icons.flag,
                ),
                _menuTile(
                  'Phương tiện: ${selectedTransport.name}',
                  Icons.directions,
                ),
                _menuTile(
                  'Tuyến xem trước: ${(plannedRouteDistanceInMeters / 1000).toStringAsFixed(2)} km',
                  Icons.alt_route,
                ),
                _menuTile(
                  'Thời gian: ${_formatDuration(plannedRouteDurationInSeconds)}',
                  Icons.access_time,
                ),
                _menuTile(
                  'Trạng thái: ${isNavigating ? 'Đang chỉ đường' : 'Chưa bắt đầu'}',
                  Icons.navigation,
                ),
                _menuTile(
                  'Còn lại: ${(remainingDistanceInMeters / 1000).toStringAsFixed(2)} km',
                  Icons.social_distance,
                ),
                _menuTile(
                  'Thời gian còn lại: ${_formatDuration(remainingDurationInSeconds)}',
                  Icons.timer,
                ),
                _menuTile(
                  'Đã đi thực tế: ${(totalDistanceInMeters / 1000).toStringAsFixed(2)} km',
                  Icons.route,
                ),
                if (isRouting)
                  _menuTile('Đang tính tuyến đường...', Icons.sync),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Marker> _buildRouteMarkers() {
    final markers = <Marker>[];

    if (startPoint != null && !isNavigating) {
      markers.add(
        Marker(
          point: startPoint!,
          width: 46,
          height: 46,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < stopPoints.length; i++) {
      markers.add(
        Marker(
          point: stopPoints[i],
          width: 46,
          height: 46,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (destinationPoint != null) {
      markers.add(
        Marker(
          point: destinationPoint!,
          width: 46,
          height: 46,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Center(
              child: Text(
                'B',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (currentLocation != null) {
      markers.add(
        Marker(
          point: currentLocation!,
          width: 52,
          height: 52,
          child: Icon(
            isNavigating ? Icons.navigation : Icons.my_location,
            color: Colors.blue,
            size: 34,
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (currentLocation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;

    return GestureDetector(
      onTap: _hideSearchPanels,
      child: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: currentLocation!,
              initialZoom: 15,
              onTap: (_, point) {
                _hideSearchPanels();
                _selectPointOnMap(point);
              },
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
                    strokeWidth: 5,
                    color: Colors.blue.withOpacity(0.25),
                  ),
                ],
              ),
              if (routedPath.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routedPath,
                      strokeWidth: 6,
                      color: Colors.orange,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  ..._buildRouteMarkers(),
                  ...savedMarkers,
                ],
              ),
            ],
          ),
          Positioned(
            top: topInset + 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: _searchHintText(),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: isSearching
                          ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                          : IconButton(
                        onPressed: () => _searchLocation(searchController.text),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 1.4,
                        ),
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        showRecentSearches =
                            searchController.text.trim().isEmpty &&
                                recentSearches.isNotEmpty;
                        showSuggestions = false;
                      });
                    },
                    onChanged: (value) {
                      _loadSuggestions(value);
                    },
                    onSubmitted: (value) {
                      _searchLocation(value);
                    },
                  ),
                ),
                _searchPanel(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _modeChip(
                      label: 'Bắt đầu',
                      icon: Icons.trip_origin,
                      mode: SearchMode.start,
                    ),
                    const SizedBox(width: 8),
                    _modeChip(
                      label: 'Dừng',
                      icon: Icons.add_location_alt,
                      mode: SearchMode.stop,
                    ),
                    const SizedBox(width: 8),
                    _modeChip(
                      label: 'Đến',
                      icon: Icons.flag,
                      mode: SearchMode.destination,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: topInset + 118,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton.small(
                heroTag: 'info_menu_btn',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: _showInfoMenu,
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 22,
                ),
              ),
            ),
          ),
          Positioned(
            top: topInset + 170,
            right: 16,
            child: Column(
              children: [
                _bottomButton(
                  icon: Icons.directions_car_rounded,
                  color: const Color(0xFF0EA5E9),
                  tooltip: 'Chọn phương tiện',
                  onPressed: _showTransportPicker,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.map_rounded,
                  color: const Color(0xFF8B5CF6),
                  tooltip: 'Đổi kiểu bản đồ',
                  onPressed: _showStylePicker,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.bookmark_added_rounded,
                  color: const Color(0xFFEC4899),
                  tooltip: 'Lưu vị trí hiện tại',
                  onPressed: _saveCurrentLocation,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.gps_fixed_rounded,
                  color: const Color(0xFF14B8A6),
                  tooltip: 'Về vị trí hiện tại',
                  onPressed: () {
                    if (currentLocation != null) {
                      mapController.move(
                        currentLocation!,
                        isNavigating ? 17 : 15,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: bottomInset + 90,
            child: Column(
              children: [
                _bottomButton(
                  icon: Icons.navigation_rounded,
                  color: isNavigating
                      ? Colors.grey.shade400
                      : const Color(0xFF16A34A),
                  tooltip: 'Bắt đầu chỉ đường',
                  onPressed: isNavigating ? null : _startNavigation,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.pause_circle_filled_rounded,
                  color: const Color(0xFFF59E0B),
                  tooltip: 'Dừng chỉ đường',
                  onPressed: _stopNavigation,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.remove_circle_rounded,
                  color: const Color(0xFF6366F1),
                  tooltip: 'Xóa điểm dừng cuối',
                  onPressed: _removeLastStop,
                ),
                const SizedBox(height: 10),
                _bottomButton(
                  icon: Icons.delete_forever_rounded,
                  color: const Color(0xFFEF4444),
                  tooltip: 'Xóa toàn bộ tuyến',
                  onPressed: _clearRoute,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}