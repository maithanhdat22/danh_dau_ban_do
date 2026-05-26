import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place_marker.dart';
import '../services/routing_service.dart';
import '../services/search_service.dart';

enum _PointEditMode { start, stop, destination }

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

class _MapWidgetState extends State<MapWidget>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _startInputController = TextEditingController();
  final TextEditingController _stopInputController = TextEditingController();
  final TextEditingController _destinationInputController =
      TextEditingController();
  final Distance _distance = const Distance();

  late final AnimationController _animationController;
  Timer? _searchDebounce;

  final List<_TripStop> _stops = [
    _TripStop(
      name: 'Hà Nội',
      address: 'Hà Nội, Việt Nam',
      point: const LatLng(21.0278, 105.8342),
    ),
    _TripStop(
      name: 'Đà Nẵng',
      address: 'Đà Nẵng, Việt Nam',
      point: const LatLng(16.0471, 108.2068),
    ),
    _TripStop(
      name: 'TP. Hồ Chí Minh',
      address: 'Thành phố Hồ Chí Minh, Việt Nam',
      point: const LatLng(10.8231, 106.6297),
    ),
  ];

  final List<_VehicleOption> _vehicles = const [
    _VehicleOption('Đi bộ', Icons.directions_walk, 'foot'),
    _VehicleOption('Xe đạp', Icons.directions_bike, 'bike'),
    _VehicleOption('Xe máy', Icons.two_wheeler, 'driving'),
    _VehicleOption('Ô tô', Icons.directions_car, 'driving'),
    _VehicleOption('Tàu hỏa', Icons.train, 'driving'),
    _VehicleOption('Máy bay', Icons.flight, 'driving'),
  ];

  final List<_MapThemeOption> _themes = const [
    _MapThemeOption(
      name: 'Cơ bản',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      routeColor: Color(0xFF2563EB),
      accentColor: Color(0xFF0F766E),
    ),
    _MapThemeOption(
      name: 'Địa hình',
      urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      routeColor: Color(0xFF16A34A),
      accentColor: Color(0xFF854D0E),
    ),
    _MapThemeOption(
      name: 'Tối giản',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      routeColor: Color(0xFF111827),
      accentColor: Color(0xFFDC2626),
    ),
  ];

  int _selectedVehicleIndex = 3;
  int _selectedThemeIndex = 0;
  _PointEditMode _editMode = _PointEditMode.stop;
  bool _isSearching = false;
  bool _isRouting = false;
  bool _panelExpanded = true;
  String? _statusText;

  List<Map<String, dynamic>> _suggestions = [];
  List<LatLng> _routePoints = [];
  List<double> _routeCumulativeMeters = [];
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _syncPointInputControllers();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildRoute(fitRoute: true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _startInputController.dispose();
    _stopInputController.dispose();
    _destinationInputController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  _VehicleOption get _vehicle => _vehicles[_selectedVehicleIndex];

  _MapThemeOption get _theme => _themes[_selectedThemeIndex];

  String get _searchHint {
    return switch (_editMode) {
      _PointEditMode.start => 'Tìm điểm đi...',
      _PointEditMode.stop => 'Tìm điểm dừng...',
      _PointEditMode.destination => 'Tìm điểm đến...',
    };
  }

  bool get _hasRoute => _routePoints.length >= 2;

  List<LatLng> get _waypoints => _stops.map((stop) => stop.point).toList();

  List<LatLng> get _animatedPath {
    if (!_hasRoute) return const [];
    if (!_animationController.isAnimating &&
        _animationController.value == 0 &&
        _routePoints.isNotEmpty) {
      return [_routePoints.first];
    }

    final targetDistance = _routeDistanceMeters * _animationController.value;
    return _slicePathAtDistance(targetDistance);
  }

  LatLng? get _vehiclePoint {
    if (!_hasRoute) return null;
    if (_animationController.value <= 0) return _routePoints.first;
    if (_animationController.value >= 1) return _routePoints.last;
    final targetDistance = _routeDistanceMeters * _animationController.value;
    return _pointAtDistance(targetDistance);
  }

  double get _vehicleBearing {
    if (!_hasRoute || _routeCumulativeMeters.length != _routePoints.length) {
      return 0;
    }

    final targetDistance = _routeDistanceMeters * _animationController.value;
    final index = _segmentIndexAtDistance(targetDistance);
    if (index >= _routePoints.length) {
      return _bearingBetween(
        _routePoints[_routePoints.length - 2],
        _routePoints.last,
      );
    }

    return _bearingBetween(_routePoints[index - 1], _routePoints[index]);
  }

  Future<void> _searchPlaces(String query) async {
    final keyword = query.trim();
    _searchDebounce?.cancel();

    if (keyword.length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 420), () async {
      setState(() => _isSearching = true);
      final results = await SearchService.searchPlaces(keyword);
      if (!mounted) return;
      setState(() {
        _suggestions = results.take(6).toList();
        _isSearching = false;
      });
    });
  }

  Future<void> _addSuggestion(Map<String, dynamic> item) async {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;

    final name = SearchService.getVietnameseName(item);
    final address = item['display_name']?.toString() ?? name;
    _applyPoint(
      _TripStop(
        name: _shortName(name),
        address: address,
        point: LatLng(lat, lon),
      ),
    );
  }

  Future<void> _searchAndApplyText(_PointEditMode mode, String query) async {
    final keyword = query.trim();
    if (keyword.length < 2) {
      setState(() => _statusText = 'Vui lòng nhập ít nhất 2 ký tự.');
      return;
    }

    setState(() {
      _editMode = mode;
      _isSearching = true;
      _statusText = 'Đang tìm địa điểm...';
    });

    final item = await SearchService.searchPlace(keyword);
    if (!mounted) return;

    if (item == null) {
      setState(() {
        _isSearching = false;
        _statusText = 'Không tìm thấy địa điểm: $keyword';
      });
      return;
    }

    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) {
      setState(() {
        _isSearching = false;
        _statusText = 'Không đọc được tọa độ của địa điểm.';
      });
      return;
    }

    final name = SearchService.getVietnameseName(item);
    final address = item['display_name']?.toString() ?? name;
    setState(() => _isSearching = false);
    _applyPoint(
      _TripStop(
        name: _shortName(name),
        address: address,
        point: LatLng(lat, lon),
      ),
      modeOverride: mode,
    );
  }

  void _addMapStop(LatLng point) {
    _applyPoint(
      _TripStop(
        name: _defaultPointName(),
        address:
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        point: point,
      ),
    );
  }

  String _defaultPointName() {
    return switch (_editMode) {
      _PointEditMode.start => 'Điểm đi',
      _PointEditMode.stop => 'Điểm dừng ${math.max(1, _stops.length - 1)}',
      _PointEditMode.destination => 'Điểm đến',
    };
  }

  void _applyPoint(_TripStop stop, {_PointEditMode? modeOverride}) {
    setState(() {
      final mode = modeOverride ?? _editMode;
      _editMode = mode;
      if (mode == _PointEditMode.start) {
        _stops[0] = stop;
        _statusText = 'Đã cập nhật điểm đi: ${stop.name}';
      } else if (mode == _PointEditMode.destination) {
        _stops[_stops.length - 1] = stop;
        _statusText = 'Đã cập nhật điểm đến: ${stop.name}';
      } else {
        _stops.insert(math.max(1, _stops.length - 1), stop);
        _statusText = 'Đã thêm điểm dừng: ${stop.name}';
      }
      _syncPointInputControllers();
      _searchController.clear();
      _suggestions = [];
    });
    _buildRoute(fitRoute: true);
  }

  void _removeStop(int index) {
    if (index == 0 || index == _stops.length - 1) {
      setState(() => _statusText = 'Chỉ xóa được điểm dừng ở giữa hành trình');
      return;
    }

    setState(() {
      _stops.removeAt(index);
      _syncPointInputControllers();
      _statusText = 'Đã xóa điểm dừng';
    });
    _buildRoute(fitRoute: true);
  }

  void _clearTrip() {
    setState(() {
      _stops
        ..clear()
        ..addAll([
          _TripStop(
            name: 'Điểm đi',
            address: 'Tìm kiếm hoặc chạm bản đồ để đặt điểm đi',
            point: const LatLng(21.0278, 105.8342),
          ),
          _TripStop(
            name: 'Điểm đến',
            address: 'Tìm kiếm hoặc chạm bản đồ để đặt điểm đến',
            point: const LatLng(10.8231, 106.6297),
          ),
        ]);
      _routePoints = [];
      _routeCumulativeMeters = [];
      _routeDistanceMeters = 0;
      _routeDurationSeconds = 0;
      _animationController.reset();
      _editMode = _PointEditMode.stop;
      _syncPointInputControllers();
      _statusText = 'Đã đặt lại hành trình';
    });
    _buildRoute(fitRoute: true);
  }

  Future<void> _buildRoute({bool fitRoute = false}) async {
    if (_stops.length < 2) return;
    setState(() {
      _isRouting = true;
      _statusText = 'Đang dựng tuyến đường...';
    });

    RouteResult? result;
    try {
      result = await RoutingService.getRoute(
        waypoints: _waypoints,
        transportName: _vehicle.routeProfile,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      result = null;
    }

    final fallbackPoints = _buildStraightRoute(_waypoints);
    final points = result != null && result.points.length >= 2
        ? result.points
        : fallbackPoints;
    final distance = result?.distanceInMeters ?? _measurePath(points);
    final duration = result?.durationInSeconds ?? _estimateDuration(distance);

    if (!mounted) return;
    setState(() {
      _routePoints = points;
      _routeCumulativeMeters = _buildCumulativeDistances(points);
      _routeDistanceMeters = distance;
      _routeDurationSeconds = duration;
      _animationController.reset();
      _isRouting = false;
      _statusText = result == null
          ? 'Đang dùng tuyến xem trước vì chưa lấy được tuyến từ mạng.'
          : 'Tuyến đường đã sẵn sàng';
    });

    if (fitRoute) _fitRoute();
  }

  void _fitRoute() {
    final points = _routePoints.isNotEmpty ? _routePoints : _waypoints;
    if (points.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(48, 96, 48, 320),
            maxZoom: 13,
          ),
        );
      } catch (_) {
        _mapController.move(points.first, 6);
      }
    });
  }

  void _playPause() {
    if (!_hasRoute) return;
    if (_animationController.isAnimating) {
      _animationController.stop();
      setState(() => _statusText = 'Đã tạm dừng');
      return;
    }
    if (_animationController.value >= 1) {
      _animationController.reset();
    }
    _animationController.forward();
    setState(() => _statusText = 'Đang phát hành trình');
  }

  void _saveDestination() {
    if (_stops.isEmpty) return;
    final stop = _stops.last;
    widget.onPlaceSaved(
      PlaceMarker(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: stop.name,
        latitude: stop.point.latitude,
        longitude: stop.point.longitude,
        createdAt: DateTime.now(),
        distanceAtSave: _routeDistanceMeters,
        transportName: _vehicle.name,
        address: stop.address,
        description:
            'Lưu từ Trình tạo hành trình bởi ${widget.currentUsername}',
      ),
    );
    setState(() => _statusText = 'Đã lưu điểm đến');
  }

  List<LatLng> _buildStraightRoute(List<LatLng> points) {
    final route = <LatLng>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      for (var step = 0; step <= 24; step++) {
        final t = step / 24;
        route.add(_lerp(start, end, t));
      }
    }
    return route;
  }

  List<LatLng> _slicePathAtDistance(double targetDistance) {
    if (_routePoints.length < 2) return _routePoints;
    if (targetDistance <= 0) return [_routePoints.first];
    if (_routeCumulativeMeters.length != _routePoints.length) {
      return _routePoints;
    }

    final index = _segmentIndexAtDistance(targetDistance);
    if (index >= _routePoints.length) return List<LatLng>.from(_routePoints);

    final previous = _routePoints[index - 1];
    final current = _routePoints[index];
    final before = _routeCumulativeMeters[index - 1];
    final segment = _routeCumulativeMeters[index] - before;
    final t = segment == 0 ? 0.0 : (targetDistance - before) / segment;

    return [
      ..._routePoints.take(index),
      _lerp(previous, current, t.clamp(0, 1)),
    ];
  }

  LatLng _pointAtDistance(double targetDistance) {
    if (_routeCumulativeMeters.length != _routePoints.length) {
      return _routePoints.last;
    }

    final index = _segmentIndexAtDistance(targetDistance);
    if (index >= _routePoints.length) return _routePoints.last;

    final previous = _routePoints[index - 1];
    final current = _routePoints[index];
    final before = _routeCumulativeMeters[index - 1];
    final segment = _routeCumulativeMeters[index] - before;
    final t = segment == 0 ? 0.0 : (targetDistance - before) / segment;
    return _lerp(previous, current, t.clamp(0, 1));
  }

  int _segmentIndexAtDistance(double targetDistance) {
    var low = 1;
    var high = _routeCumulativeMeters.length - 1;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_routeCumulativeMeters[mid] < targetDistance) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  LatLng _lerp(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _measurePath(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return total;
  }

  List<double> _buildCumulativeDistances(List<LatLng> points) {
    if (points.isEmpty) return const [];
    final cumulative = <double>[0];
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
      cumulative.add(total);
    }
    return cumulative;
  }

  double _estimateDuration(double meters) {
    final speedKmh = switch (_vehicle.routeProfile) {
      'foot' => 5.0,
      'bike' => 16.0,
      _ => 55.0,
    };
    return meters / (speedKmh * 1000 / 3600);
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  String _shortName(String value) {
    final first = value.split(',').first.trim();
    if (first.length <= 28) return first;
    return '${first.substring(0, 25)}...';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remain = minutes % 60;
      return '${hours}h ${remain}m';
    }
    return '${math.max(1, minutes)}m';
  }

  void _syncPointInputControllers() {
    if (_stops.isEmpty) return;
    _startInputController.text = _stops.first.name;
    _destinationInputController.text = _stops.last.name;
    _stopInputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(16.0471, 108.2068),
              initialZoom: 5.5,
              onTap: (_, point) => _addMapStop(point),
            ),
            children: [
              TileLayer(
                urlTemplate: _theme.urlTemplate,
                userAgentPackageName: 'com.example.ban_do',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.white,
                      strokeWidth: 8,
                    ),
                    Polyline(
                      points: _routePoints,
                      color: _theme.routeColor.withValues(alpha: 0.35),
                      strokeWidth: 5,
                    ),
                  ],
                ),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final animatedPath = _animatedPath;
                  if (animatedPath.length < 2) return const SizedBox.shrink();
                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: animatedPath,
                        color: _theme.routeColor,
                        strokeWidth: 6,
                      ),
                    ],
                  );
                },
              ),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final vehiclePoint = _vehiclePoint;
                  return MarkerLayer(
                    markers: [
                      ..._buildStopMarkers(),
                      if (vehiclePoint != null)
                        _buildVehicleMarker(vehiclePoint),
                    ],
                  );
                },
              ),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                _SearchBar(
                  controller: _searchController,
                  isSearching: _isSearching,
                  hintText: _searchHint,
                  onChanged: _searchPlaces,
                  onClear: () {
                    setState(() {
                      _searchController.clear();
                      _suggestions = [];
                    });
                  },
                ),
                if (_suggestions.isNotEmpty)
                  _SuggestionList(
                    suggestions: _suggestions,
                    onSelect: _addSuggestion,
                  ),
                _ModeSelector(
                  selectedMode: _editMode,
                  onChanged: (mode) {
                    setState(() {
                      _editMode = mode;
                      _statusText = switch (mode) {
                        _PointEditMode.start => 'Đang chỉnh điểm đi',
                        _PointEditMode.stop => 'Đang thêm điểm dừng',
                        _PointEditMode.destination => 'Đang chỉnh điểm đến',
                      };
                    });
                  },
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return _TripPanel(
                          expanded: _panelExpanded,
                          stops: _stops,
                          vehicles: _vehicles,
                          themes: _themes,
                          selectedVehicleIndex: _selectedVehicleIndex,
                          selectedThemeIndex: _selectedThemeIndex,
                          editMode: _editMode,
                          isRouting: _isRouting,
                          isPlaying: _animationController.isAnimating,
                          progress: _animationController.value,
                          distance: _formatDistance(_routeDistanceMeters),
                          duration: _formatDuration(_routeDurationSeconds),
                          statusText: _statusText,
                          onToggleExpanded: () {
                            setState(() => _panelExpanded = !_panelExpanded);
                          },
                          onVehicleSelected: (index) {
                            setState(() => _selectedVehicleIndex = index);
                            _buildRoute();
                          },
                          onThemeSelected: (index) {
                            setState(() => _selectedThemeIndex = index);
                          },
                          onRemoveStop: _removeStop,
                          startController: _startInputController,
                          stopController: _stopInputController,
                          destinationController: _destinationInputController,
                          onPointSubmitted: _searchAndApplyText,
                          onPlayPause: _playPause,
                          onResetAnimation: () {
                            setState(() {
                              _animationController.reset();
                              _statusText = 'Đã tua lại animation';
                            });
                          },
                          onFitRoute: _fitRoute,
                          onClearTrip: _clearTrip,
                          onSaveDestination: _saveDestination,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildStopMarkers() {
    return List.generate(_stops.length, (index) {
      final stop = _stops[index];
      final isFirst = index == 0;
      final isLast = index == _stops.length - 1;
      final color = isFirst
          ? const Color(0xFF16A34A)
          : isLast
          ? const Color(0xFFDC2626)
          : _theme.accentColor;
      final label = isFirst
          ? 'A'
          : isLast
          ? 'B'
          : '$index';

      return Marker(
        point: stop.point,
        width: 48,
        height: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: color, size: 22),
          ],
        ),
      );
    });
  }

  Marker _buildVehicleMarker(LatLng point) {
    return Marker(
      point: point,
      width: 58,
      height: 58,
      child: Transform.rotate(
        angle: _vehicle.name == 'Máy bay' ? _vehicleBearing : 0,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _theme.routeColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(_vehicle.icon, color: _theme.routeColor, size: 26),
        ),
      ),
    );
  }
}

class _TripStop {
  final String name;
  final String address;
  final LatLng point;

  const _TripStop({
    required this.name,
    required this.address,
    required this.point,
  });
}

class _VehicleOption {
  final String name;
  final IconData icon;
  final String routeProfile;

  const _VehicleOption(this.name, this.icon, this.routeProfile);
}

class _MapThemeOption {
  final String name;
  final String urlTemplate;
  final Color routeColor;
  final Color accentColor;

  const _MapThemeOption({
    required this.name,
    required this.urlTemplate,
    required this.routeColor,
    required this.accentColor,
  });
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.isSearching,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Material(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search),
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
                    tooltip: 'Xóa nội dung tìm kiếm',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const _SuggestionList({required this.suggestions, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          final name = SearchService.getVietnameseName(item);
          final address = item['display_name']?.toString() ?? name;
          return ListTile(
            dense: true,
            leading: const Icon(Icons.add_location_alt_outlined),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelect(item),
          );
        },
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final _PointEditMode selectedMode;
  final ValueChanged<_PointEditMode> onChanged;

  const _ModeSelector({required this.selectedMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _ModeButton(
            icon: Icons.trip_origin,
            label: 'Điểm đi',
            selected: selectedMode == _PointEditMode.start,
            onTap: () => onChanged(_PointEditMode.start),
          ),
          _ModeButton(
            icon: Icons.add_location_alt_outlined,
            label: 'Điểm dừng',
            selected: selectedMode == _PointEditMode.stop,
            onTap: () => onChanged(_PointEditMode.stop),
          ),
          _ModeButton(
            icon: Icons.flag,
            label: 'Điểm đến',
            selected: selectedMode == _PointEditMode.destination,
            onTap: () => onChanged(_PointEditMode.destination),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFDBEAFE) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? const Color(0xFF2563EB) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFF475569),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripPanel extends StatelessWidget {
  final bool expanded;
  final List<_TripStop> stops;
  final List<_VehicleOption> vehicles;
  final List<_MapThemeOption> themes;
  final int selectedVehicleIndex;
  final int selectedThemeIndex;
  final _PointEditMode editMode;
  final bool isRouting;
  final bool isPlaying;
  final double progress;
  final String distance;
  final String duration;
  final String? statusText;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onVehicleSelected;
  final ValueChanged<int> onThemeSelected;
  final ValueChanged<int> onRemoveStop;
  final TextEditingController startController;
  final TextEditingController stopController;
  final TextEditingController destinationController;
  final void Function(_PointEditMode mode, String query) onPointSubmitted;
  final VoidCallback onPlayPause;
  final VoidCallback onResetAnimation;
  final VoidCallback onFitRoute;
  final VoidCallback onClearTrip;
  final VoidCallback onSaveDestination;

  const _TripPanel({
    required this.expanded,
    required this.stops,
    required this.vehicles,
    required this.themes,
    required this.selectedVehicleIndex,
    required this.selectedThemeIndex,
    required this.editMode,
    required this.isRouting,
    required this.isPlaying,
    required this.progress,
    required this.distance,
    required this.duration,
    required this.statusText,
    required this.onToggleExpanded,
    required this.onVehicleSelected,
    required this.onThemeSelected,
    required this.onRemoveStop,
    required this.startController,
    required this.stopController,
    required this.destinationController,
    required this.onPointSubmitted,
    required this.onPlayPause,
    required this.onResetAnimation,
    required this.onFitRoute,
    required this.onClearTrip,
    required this.onSaveDestination,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      constraints: BoxConstraints(
        maxHeight: expanded ? MediaQuery.of(context).size.height * 0.68 : 190,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tạo hành trình',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                if (isRouting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: expanded ? 'Thu gọn' : 'Mở rộng',
                  onPressed: onToggleExpanded,
                  icon: Icon(expanded ? Icons.expand_more : Icons.expand_less),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MetricChip(icon: Icons.straighten, label: distance),
                const SizedBox(width: 8),
                _MetricChip(icon: Icons.schedule, label: duration),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: vehicles[selectedVehicleIndex].icon,
                  label: vehicles[selectedVehicleIndex].name,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 6,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                switch (editMode) {
                  _PointEditMode.start =>
                    'Tìm kiếm hoặc chạm bản đồ để đổi điểm đi.',
                  _PointEditMode.stop =>
                    'Tìm kiếm hoặc chạm bản đồ để thêm điểm dừng.',
                  _PointEditMode.destination =>
                    'Tìm kiếm hoặc chạm bản đồ để đổi điểm đến.',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 10),
              _RouteInputForm(
                startController: startController,
                stopController: stopController,
                destinationController: destinationController,
                onPointSubmitted: onPointSubmitted,
              ),
              const SizedBox(height: 10),
              _IconScroller(
                label: 'Phương tiện',
                itemCount: vehicles.length,
                selectedIndex: selectedVehicleIndex,
                iconAt: (index) => vehicles[index].icon,
                textAt: (index) => vehicles[index].name,
                onSelected: onVehicleSelected,
              ),
              const SizedBox(height: 10),
              _ThemeScroller(
                themes: themes,
                selectedIndex: selectedThemeIndex,
                onSelected: onThemeSelected,
              ),
              const SizedBox(height: 10),
              ListView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  return _StopTile(
                    index: index,
                    totalCount: stops.length,
                    stop: stop,
                    canRemove: index > 0 && index < stops.length - 1,
                    onRemove: () => onRemoveStop(index),
                  );
                },
              ),
            ],
            if (statusText != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  statusText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filled(
                  tooltip: isPlaying ? 'Tạm dừng' : 'Phát',
                  onPressed: isRouting ? null : onPlayPause,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const Spacer(),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Tua lại animation',
                  onPressed: onResetAnimation,
                  icon: const Icon(Icons.replay),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Canh giữa tuyến đường',
                  onPressed: onFitRoute,
                  icon: const Icon(Icons.center_focus_strong),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn',
                  onSelected: (value) {
                    if (value == 'save') onSaveDestination();
                    if (value == 'clear') onClearTrip();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'save', child: Text('Lưu điểm đến')),
                    PopupMenuItem(
                      value: 'clear',
                      child: Text('Đặt lại hành trình'),
                    ),
                  ],
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.more_vert),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteInputForm extends StatelessWidget {
  final TextEditingController startController;
  final TextEditingController stopController;
  final TextEditingController destinationController;
  final void Function(_PointEditMode mode, String query) onPointSubmitted;

  const _RouteInputForm({
    required this.startController,
    required this.stopController,
    required this.destinationController,
    required this.onPointSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PointInputField(
          controller: startController,
          icon: Icons.trip_origin,
          label: 'Điểm xuất phát',
          hint: 'Nhập nơi bắt đầu',
          color: const Color(0xFF16A34A),
          onSubmitted: (value) => onPointSubmitted(_PointEditMode.start, value),
        ),
        const SizedBox(height: 8),
        _PointInputField(
          controller: stopController,
          icon: Icons.add_location_alt_outlined,
          label: 'Điểm dừng',
          hint: 'Nhập điểm dừng muốn ghé',
          color: const Color(0xFF2563EB),
          onSubmitted: (value) => onPointSubmitted(_PointEditMode.stop, value),
        ),
        const SizedBox(height: 8),
        _PointInputField(
          controller: destinationController,
          icon: Icons.flag,
          label: 'Điểm đến',
          hint: 'Nhập nơi kết thúc',
          color: const Color(0xFFDC2626),
          onSubmitted: (value) =>
              onPointSubmitted(_PointEditMode.destination, value),
        ),
      ],
    );
  }
}

class _PointInputField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final Color color;
  final ValueChanged<String> onSubmitted;

  const _PointInputField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: color, size: 20),
          suffixIcon: IconButton(
            tooltip: 'Tìm địa điểm',
            onPressed: () => onSubmitted(controller.text),
            icon: const Icon(Icons.search),
          ),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: const Color(0xFF334155)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconScroller extends StatelessWidget {
  final String label;
  final int itemCount;
  final int selectedIndex;
  final IconData Function(int index) iconAt;
  final String Function(int index) textAt;
  final ValueChanged<int> onSelected;

  const _IconScroller({
    required this.label,
    required this.itemCount,
    required this.selectedIndex,
    required this.iconAt,
    required this.textAt,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = index == selectedIndex;
                return Tooltip(
                  message: textAt(index),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelected(index),
                    child: Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFDBEAFE)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconAt(index),
                            size: 22,
                            color: selected
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF475569),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            textAt(index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeScroller extends StatelessWidget {
  final List<_MapThemeOption> themes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _ThemeScroller({
    required this.themes,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const SizedBox(
            width: 58,
            child: Text(
              'Kiểu bản đồ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: themes.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final theme = themes[index];
                final selected = index == selectedIndex;
                return ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: CircleAvatar(backgroundColor: theme.routeColor),
                  label: Text(theme.name),
                  onSelected: (_) => onSelected(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final int index;
  final int totalCount;
  final _TripStop stop;
  final bool canRemove;
  final VoidCallback onRemove;

  const _StopTile({
    required this.index,
    required this.totalCount,
    required this.stop,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = index == 0
        ? 'A'
        : index == totalCount - 1
        ? 'B'
        : '$index';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: index == 0
                ? const Color(0xFF16A34A)
                : index == totalCount - 1
                ? const Color(0xFFDC2626)
                : const Color(0xFF2563EB),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  stop.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Xóa điểm dừng',
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
