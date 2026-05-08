import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_style_option.dart';
import '../models/place_marker.dart';
import '../models/transport_option.dart';
import '../services/location_service.dart';
import '../services/search_service.dart';
import '../services/sound_service.dart';

enum SearchMode { start, stop, destination }

// Parse route JSON ngoài main isolate để app đỡ giật.
List<LatLng> _parseRouteIsolate(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  if (data['code'] != 'Ok') return [];

  final route = (data['routes'] as List).first as Map<String, dynamic>;
  final rawCoords = (route['geometry'] as Map)['coordinates'] as List;

  return rawCoords
      .map((e) => LatLng(
    (e[1] as num).toDouble(),
    (e[0] as num).toDouble(),
  ))
      .toList();
}

Map<String, dynamic> _parseRouteMeta(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  if (data['code'] != 'Ok') return {};

  final route = (data['routes'] as List).first as Map<String, dynamic>;

  return {
    'distance': (route['distance'] as num).toDouble(),
    'duration': (route['duration'] as num).toDouble(),
  };
}

Future<Map<String, dynamic>> _parseRouteInBackground(String body) async {
  final points = _parseRouteIsolate(body);
  final meta = _parseRouteMeta(body);

  return {
    'points': points,
    'distance': meta['distance'] ?? 0.0,
    'duration': meta['duration'] ?? 0.0,
  };
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
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final Distance _distance = const Distance();

  LatLng? _currentLocation;
  double? _currentAccuracy;

  // Xoay bản đồ theo hướng di chuyển khi đang chỉ đường giống Google Maps.
  double _cameraBearing = 0;
  bool _autoRotateMap = true;

  // Âm thanh chỉ đường giống Google Maps.
  bool _voiceEnabled = true;
  DateTime _lastDistanceVoice = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastDistanceBucket = -1;

  static const int _maxBreadcrumb = 300;
  final List<LatLng> _breadcrumb = [];

  LatLng? _startPoint;
  String _startName = 'Vị trí hiện tại';

  final List<LatLng> _stopPoints = [];
  final List<String> _stopNames = [];

  LatLng? _destinationPoint;
  String _destinationName = '';

  List<LatLng> _routedPath = [];

  double _plannedDistM = 0;
  double _plannedDurS = 0;
  double _remainingDistM = 0;
  double _remainingDurS = 0;
  double _totalDistM = 0;

  bool _isRouting = false;
  bool _isNavigating = false;
  bool _followLocation = true;

  SearchMode _searchMode = SearchMode.destination;
  Map<String, dynamic>? _selectedPlace;

  final List<String> _recentSearches = [];
  bool _showRecent = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  String _searchKeyword = '';

  MapStyleOption _mapStyle = MapStylePresets.presets.first;
  TransportOption _transport = TransportOptions.items.first;

  final List<Marker> _savedMarkers = [];

  StreamSubscription<dynamic>? _locationSub;
  Timer? _debounce;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadRecentSearches();
    _initLocation();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    SoundService.stop();
    super.dispose();
  }

  String get _tileUrl {
    switch (_mapStyle.baseMapType) {
      case BaseMapType.osmStandard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case BaseMapType.openTopo:
        return 'https://tile.openmaps.fr/opentopomap/{z}/{x}/{y}.png';
    }
  }

  void _loadRecentSearches() {
    final items = _prefs?.getStringList('recent_searches') ?? [];
    if (!mounted) return;
    setState(() {
      _recentSearches
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _saveRecentSearches() async {
    await _prefs?.setStringList('recent_searches', _recentSearches);
  }

  Future<void> _savePlaceToDevice(PlaceMarker place) async {
    final items = _prefs?.getStringList('saved_places') ?? [];

    final exists = items.any((raw) {
      try {
        return (jsonDecode(raw) as Map<String, dynamic>)['id'] == place.id;
      } catch (_) {
        return false;
      }
    });

    if (!exists) {
      items.insert(0, place.toJson());
      await _prefs?.setStringList('saved_places', items);
    }
  }

  void _moveSafely(LatLng point, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (_isNavigating && _autoRotateMap) {
          _mapController.moveAndRotate(point, zoom, _cameraBearing);
        } else {
          _mapController.move(point, zoom);
        }
      } catch (_) {}
    });
  }

  LatLng? _nextRoutePointFrom(LatLng current) {
    if (_routedPath.length < 2) return _destinationPoint;

    for (final p in _routedPath) {
      final d = _distance.as(LengthUnit.Meter, current, p);
      if (d > 28) return p;
    }

    return _destinationPoint;
  }

  void _updateCameraBearing(LatLng current, LatLng next) {
    if (!_isNavigating || !_autoRotateMap) return;

    final routeNext = _nextRoutePointFrom(next);
    if (routeNext != null) {
      _cameraBearing = _bearing(next, routeNext);
      return;
    }

    final moved = _distance.as(LengthUnit.Meter, current, next);
    if (moved >= 5) {
      _cameraBearing = _bearing(current, next);
    }
  }


  Future<void> _speakNow(String text) async {
    if (!_voiceEnabled) return;
    await SoundService.speakNow(text);
  }

  Future<void> _speak(String text, {int gapSeconds = 8}) async {
    if (!_voiceEnabled) return;
    await SoundService.speak(text, gapSeconds: gapSeconds);
  }

  String _speakDistanceText(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} ki lô mét';
    }
    return '${meters.round()} mét';
  }

  Future<void> _maybeSpeakNavigationProgress(LatLng current) async {
    if (!_isNavigating || !_voiceEnabled) return;

    final distance = _remainingDistM > 0 ? _remainingDistM : _plannedDistM;
    if (distance <= 0) return;

    // Nói khoảng cách theo mốc, tránh nói liên tục làm lag/ồn.
    int bucket;
    if (distance > 5000) {
      bucket = (distance / 1000).floor();
    } else if (distance > 1000) {
      bucket = (distance / 500).floor();
    } else {
      bucket = (distance / 100).floor();
    }

    final now = DateTime.now();
    final enoughTime = now.difference(_lastDistanceVoice).inSeconds >= 25;
    if (bucket != _lastDistanceBucket && enoughTime) {
      _lastDistanceBucket = bucket;
      _lastDistanceVoice = now;
      await _speak('Còn ${_speakDistanceText(distance)} nữa tới điểm đến', gapSeconds: 20);
    }

    final routeNext = _nextRoutePointFrom(current);
    if (routeNext != null) {
      final dToNext = _distance.as(LengthUnit.Meter, current, routeNext);
      if (dToNext <= 80 && enoughTime) {
        _lastDistanceVoice = now;
        await _speak('${_bearingDirectionText()}, sau đó tiếp tục đi theo tuyến đường', gapSeconds: 12);
      }
    }
  }

  void _fitSafely(List<LatLng> points) {
    if (points.length < 2) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(80),
          ),
        );
      } catch (_) {}
    });
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted) return;

    final first = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentLocation = first;
      _currentAccuracy = pos.accuracy;
      _breadcrumb.add(first);
      _startPoint = first;
    });

    _moveSafely(first, 15);
    _startTracking();
  }

  void _startTracking() {
    _locationSub?.cancel();

    final stream = _isNavigating
        ? LocationService.getNavigationStream()
        : LocationService.getPositionStream();

    _locationSub = stream.listen((pos) async {
      if (!mounted) return;

      final next = LatLng(pos.latitude, pos.longitude);
      bool shouldReroute = false;

      final previous = _currentLocation;
      if (previous != null) {
        _updateCameraBearing(previous, next);
      }

      setState(() {
        if (_currentLocation != null) {
          final delta = _distance.as(
            LengthUnit.Meter,
            _currentLocation!,
            next,
          );

          if (delta >= 12) {
            _totalDistM += delta;

            if (_breadcrumb.length >= _maxBreadcrumb) {
              _breadcrumb.removeAt(0);
            }

            _breadcrumb.add(next);
          }

          if (_isNavigating && delta >= 30) {
            shouldReroute = true;
          }
        }

        _currentLocation = next;
        _currentAccuracy = pos.accuracy;
      });

      if (_followLocation || _isNavigating) {
        _moveSafely(next, _isNavigating ? 17 : 16);
      }

      if (_isNavigating) {
        if (shouldReroute) await _buildNavigationRoute();

        await _maybeSpeakNavigationProgress(next);

        if (_remainingDistM > 0 && _remainingDistM <= 30 && mounted) {
          await _speakNow('Bạn đã gần tới điểm đến');
          setState(() => _isNavigating = false);
          _showSnack('Bạn đã gần tới điểm đến');
          _startTracking();
        }
      }
    });
  }

  void _addRecent(String value) {
    final kw = value.trim();
    if (kw.isEmpty) return;

    setState(() {
      _recentSearches.remove(kw);
      _recentSearches.insert(0, kw);
      if (_recentSearches.length > 10) _recentSearches.removeLast();
    });

    _saveRecentSearches();
  }

  void _hideSearchPanels() {
    if (!mounted) return;

    setState(() {
      _showRecent = false;
      _showSuggestions = false;
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final kw = query.trim();

    if (kw.isEmpty) {
      if (!mounted) return;

      setState(() {
        _searchKeyword = '';
        _suggestions = [];
        _showSuggestions = false;
        _showRecent = _recentSearches.isNotEmpty;
        _isSearching = false;
      });

      return;
    }

    setState(() {
      _searchKeyword = kw;
      _isSearching = true;
      _showRecent = false;
      _showSuggestions = true;
    });

    final snapshot = kw;
    final results = await SearchService.searchPlaces(kw);

    if (!mounted || _searchKeyword != snapshot) return;

    setState(() {
      _suggestions = results;
      _showSuggestions = true;
      _isSearching = false;
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> item) async {
    final lat = double.tryParse(item['lat'].toString());
    final lon = double.tryParse(item['lon'].toString());
    final name = SearchService.getVietnameseName(item);

    if (lat == null || lon == null) return;

    final point = LatLng(lat, lon);
    final title = name.isNotEmpty ? name : 'Địa điểm đã chọn';

    // Ảnh chỉ được fetch/hiện SAU KHI bấm chọn địa điểm ở đây.
    _setPlaceInfo(
      title: title,
      address: name.isNotEmpty ? name : title,
      point: point,
    );

    _addRecent(title);
    _applyPointToMode(point, title);
    _afterPointSelected(point);
  }

  Future<void> _searchLocation(String query) async {
    final kw = query.trim();
    if (kw.isEmpty) return;

    _addRecent(kw);

    final result = await SearchService.searchPlace(kw);

    if (result == null) {
      if (mounted) _showSnack('Không tìm thấy địa điểm');
      return;
    }

    final lat = double.tryParse(result['lat'].toString());
    final lon = double.tryParse(result['lon'].toString());

    if (lat == null || lon == null) return;

    final point = LatLng(lat, lon);
    final title = SearchService.getVietnameseName(result);
    final address = (result['display_name'] ?? title).toString();

    // Ảnh chỉ hiện sau khi người dùng submit/chọn địa điểm.
    _setPlaceInfo(title: title, address: address, point: point);

    _applyPointToMode(point, title);
    _afterPointSelected(point);
  }

  void _applyPointToMode(LatLng point, String title) {
    setState(() {
      switch (_searchMode) {
        case SearchMode.start:
          _startPoint = point;
          _startName = title;
          break;
        case SearchMode.stop:
          _stopPoints.add(point);
          _stopNames.add(title);
          break;
        case SearchMode.destination:
          _destinationPoint = point;
          _destinationName = title;
          break;
      }

      _showSuggestions = false;
      _showRecent = false;
    });
  }

  Future<void> _afterPointSelected(LatLng point) async {
    final waypoints = _previewWaypoints();

    if (waypoints.length >= 2) {
      _fitSafely(waypoints);
    } else {
      _moveSafely(point, 15);
    }

    await _buildPreviewRoute();

    if (!mounted) return;

    _searchController.clear();

    setState(() => _searchMode = SearchMode.destination);
  }

  void _selectPointOnMap(LatLng point) {
    final coord =
        'Lat ${point.latitude.toStringAsFixed(5)}, Lng ${point.longitude.toStringAsFixed(5)}';

    _setPlaceInfo(
      title: 'Địa điểm đã chọn',
      address: coord,
      point: point,
    );

    _applyPointToMode(point, coord);

    final wp = _previewWaypoints();

    if (wp.length >= 2) {
      _fitSafely(wp);
    } else {
      _moveSafely(point, 15);
    }

    _buildPreviewRoute();
    _showSnack('Đã chọn điểm: $coord');
  }

  void _selectRecentSearch(String value) {
    _searchController.text = value;
    _searchLocation(value);
  }

  String get _osrmProfile {
    final name = _transport.name.toLowerCase();

    if (name.contains('đi bộ')) return 'foot';
    if (name.contains('xe đạp')) return 'bike';

    return 'driving';
  }

  List<LatLng> _previewWaypoints() {
    return [
      if (_startPoint != null) _startPoint!,
      ..._stopPoints,
      if (_destinationPoint != null) _destinationPoint!,
    ];
  }

  List<LatLng> _navigationWaypoints() {
    return [
      if (_currentLocation != null)
        _currentLocation!
      else if (_startPoint != null)
        _startPoint!,
      ..._stopPoints,
      if (_destinationPoint != null) _destinationPoint!,
    ];
  }

  Future<void> _requestRoute({
    required List<LatLng> waypoints,
    required bool forNavigation,
  }) async {
    if (waypoints.length < 2) {
      setState(() {
        _routedPath = [];
        _plannedDistM = 0;
        _plannedDurS = 0;
        _remainingDistM = 0;
        _remainingDurS = 0;
      });

      return;
    }

    setState(() => _isRouting = true);

    try {
      final coords = waypoints
          .map((e) => '${e.longitude},${e.latitude}')
          .join(';');

      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/$_osrmProfile/$coords'
            '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('OSRM ${response.statusCode}');
      }

      final result = await compute(_parseRouteInBackground, response.body);

      final points = result['points'] as List<LatLng>;
      final dist = result['distance'] as double;
      final dur = result['duration'] as double;

      if (points.isEmpty) {
        throw Exception('Route not found');
      }

      if (!mounted) return;

      setState(() {
        _routedPath = points;
        _plannedDistM = dist;
        _plannedDurS = dur;

        if (forNavigation) {
          _remainingDistM = dist;
          _remainingDurS = dur;
        }

        _isRouting = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _isRouting = false);
      _showSnack('Không tìm được tuyến đường');
    }
  }

  Future<void> _buildPreviewRoute() {
    return _requestRoute(
      waypoints: _previewWaypoints(),
      forNavigation: false,
    );
  }

  Future<void> _buildNavigationRoute() {
    return _requestRoute(
      waypoints: _navigationWaypoints(),
      forNavigation: true,
    );
  }

  Future<void> _startNavigation() async {
    if (_destinationPoint == null) {
      _showSnack('Hãy chọn điểm đến trước');
      return;
    }

    setState(() {
      _isNavigating = true;
      _showRecent = false;
      _showSuggestions = false;
      _selectedPlace = null;
      _followLocation = true;
      _lastDistanceBucket = -1;
      _lastDistanceVoice = DateTime.fromMillisecondsSinceEpoch(0);
    });

    await _speakNow('Bắt đầu chỉ đường');

    _startTracking();

    await _buildNavigationRoute();

    if (!mounted) return;

    if (_currentLocation != null) {
      _moveSafely(_currentLocation!, 17);
    }

    _showSnack('Đã bắt đầu chỉ đường');
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _remainingDistM = _plannedDistM;
      _remainingDurS = _plannedDurS;
      _cameraBearing = 0;
    });
    try {
      _mapController.rotate(0);
    } catch (_) {}

    _speakNow('Đã dừng chỉ đường');
    _startTracking();
    _showSnack('Đã dừng chỉ đường');
  }

  void _removeLastStop() {
    if (_stopPoints.isEmpty) return;

    setState(() {
      _stopPoints.removeLast();
      _stopNames.removeLast();
    });

    _isNavigating ? _buildNavigationRoute() : _buildPreviewRoute();
  }

  void _clearRoute() {
    setState(() {
      _startPoint = _currentLocation;
      _startName = 'Vị trí hiện tại';
      _stopPoints.clear();
      _stopNames.clear();
      _destinationPoint = null;
      _destinationName = '';
      _routedPath = [];
      _plannedDistM = 0;
      _plannedDurS = 0;
      _remainingDistM = 0;
      _remainingDurS = 0;
      _isNavigating = false;
      _cameraBearing = 0;
      _searchMode = SearchMode.destination;
      _showRecent = false;
      _showSuggestions = false;
      _selectedPlace = null;
    });
  }

  String _coordText(LatLng p) {
    return 'Lat: ${p.latitude.toStringAsFixed(6)}, Lng: ${p.longitude.toStringAsFixed(6)}';
  }

  Future<void> _setPlaceInfo({
    required String title,
    required String address,
    required LatLng point,
  }) async {
    final addr = address.isNotEmpty ? address : _coordText(point);

    if (mounted) {
      setState(() {
        _selectedPlace = {
          'title': title,
          'address': addr,
          'lat': point.latitude,
          'lon': point.longitude,
          'imageUrl': '',
        };
      });
    }

    final imageUrl = await SearchService.fetchPlaceImage(title);

    if (!mounted) return;

    setState(() {
      _selectedPlace = {
        'title': title,
        'address': addr,
        'lat': point.latitude,
        'lon': point.longitude,
        'imageUrl': imageUrl ?? '',
      };
    });
  }

  void _closePlaceInfo() {
    setState(() => _selectedPlace = null);
  }

  void _saveSelectedPlace() {
    final info = _selectedPlace;
    if (info == null) return;

    final lat = (info['lat'] as num).toDouble();
    final lon = (info['lon'] as num).toDouble();
    final title = info['title'].toString();
    final address = info['address'].toString();
    final imageUrl = info['imageUrl'].toString();
    final point = LatLng(lat, lon);
    final now = DateTime.now();

    setState(() => _savedMarkers.add(_savedMarker(point)));

    final place = PlaceMarker(
      id: now.millisecondsSinceEpoch.toString(),
      title: title,
      latitude: lat,
      longitude: lon,
      createdAt: now,
      distanceAtSave: _totalDistM,
      transportName: _transport.name,
      description: 'Địa điểm đã được lưu từ bản đồ',
      imageUrl: imageUrl,
      address: address,
    );

    widget.onPlaceSaved(place);
    _savePlaceToDevice(place);
    _showSnack('Đã lưu địa điểm');
  }

  void _saveCurrentLocation() {
    if (_currentLocation == null) return;

    final point = _currentLocation!;
    final now = DateTime.now();
    final title = 'Vị trí ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    setState(() => _savedMarkers.add(_savedMarker(point)));

    final place = PlaceMarker(
      id: now.millisecondsSinceEpoch.toString(),
      title: title,
      latitude: point.latitude,
      longitude: point.longitude,
      createdAt: now,
      distanceAtSave: _totalDistM,
      transportName: _transport.name,
      description: 'Địa điểm đã đi qua và được lưu từ bản đồ',
      imageUrl: '',
      address: _coordText(point),
    );

    widget.onPlaceSaved(place);
    _savePlaceToDevice(place);
    _showSnack('Đã lưu vị trí');
  }

  Marker _savedMarker(LatLng point) {
    return Marker(
      point: point,
      width: 46,
      height: 46,
      child: Icon(
        Icons.location_pin,
        color: _mapStyle.theme.savedMarkerColor,
        size: 38,
      ),
    );
  }

  String _fmtDuration(double seconds) {
    if (seconds <= 0) return '0 phút';

    final m = (seconds / 60).round();
    final h = m ~/ 60;
    final rem = m % 60;

    if (h == 0) return '$m phút';

    return '$h giờ ${rem.toString().padLeft(2, '0')} phút';
  }

  String _arrivalTimeText(double seconds) {
    if (seconds <= 0) return '--:--';

    final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
    final h = arrival.hour.toString().padLeft(2, '0');
    final m = arrival.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }

  String _distanceText(double meters) {
    if (meters <= 0) return '0 km';

    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return '${meters.toStringAsFixed(0)} m';
  }

  String _bearingDirectionText() {
    if (_currentLocation == null || _routedPath.length < 2) {
      return 'Đi theo tuyến đường';
    }

    LatLng? nextPoint;

    for (final p in _routedPath) {
      final d = _distance.as(LengthUnit.Meter, _currentLocation!, p);
      if (d > 25) {
        nextPoint = p;
        break;
      }
    }

    nextPoint ??= _destinationPoint;

    if (nextPoint == null) return 'Đi theo tuyến đường';

    final bearing = _bearing(_currentLocation!, nextPoint);

    final dirs = [
      'Bắc',
      'Đông Bắc',
      'Đông',
      'Đông Nam',
      'Nam',
      'Tây Nam',
      'Tây',
      'Tây Bắc',
    ];

    final index = ((bearing + 22.5) ~/ 45) % 8;

    return 'Đi về hướng ${dirs[index]}';
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final brng = math.atan2(y, x) * 180 / math.pi;

    return (brng + 360) % 360;
  }

  void _showSnack(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  IconData _iconFor(String text) {
    final v = text.toLowerCase();

    if (v.contains('sân bay') || v.contains('airport')) {
      return Icons.flight_takeoff_rounded;
    }
    if (v.contains('sân vận động') || v.contains('stadium')) {
      return Icons.sports_soccer_rounded;
    }
    if (v.contains('bệnh viện') || v.contains('hospital')) {
      return Icons.local_hospital_rounded;
    }
    if (v.contains('trường') || v.contains('đại học') || v.contains('school')) {
      return Icons.school_rounded;
    }
    if (v.contains('cafe') || v.contains('cà phê') || v.contains('coffee')) {
      return Icons.local_cafe_rounded;
    }
    if (v.contains('khách sạn') || v.contains('hotel')) {
      return Icons.hotel_rounded;
    }
    if (v.contains('nhà hàng') ||
        v.contains('quán ăn') ||
        v.contains('restaurant')) {
      return Icons.restaurant_rounded;
    }
    if (v.contains('đường') || v.contains('phố') || v.contains('ngõ')) {
      return Icons.route_rounded;
    }

    return Icons.location_on_outlined;
  }

  List<String> _smartSuggestions(String keyword) {
    final q = keyword.toLowerCase().trim();

    if (q.isEmpty) return [];

    final suggestions = <String>[];

    if ('sân bay'.contains(q) || q.contains('sân bay')) {
      suggestions.addAll([
        'Sân bay Nội Bài',
        'Sân bay Tân Sơn Nhất',
        'Sân bay Cát Bi',
        'Sân bay Đà Nẵng',
      ]);
    } else if (q.contains('sân vận động') ||
        q.contains('sân bóng') ||
        q == 'sân') {
      suggestions.addAll([
        'Sân vận động Quốc gia Mỹ Đình',
        'Sân vận động Hàng Đẫy',
        'Sân bóng Mỹ Đình',
      ]);
    } else if ('bệnh viện'.contains(q) || q.contains('bệnh viện')) {
      suggestions.addAll([
        'Bệnh viện Bạch Mai',
        'Bệnh viện Việt Đức',
        'Bệnh viện 108 Hà Nội',
        'Bệnh viện Nhi Trung ương',
      ]);
    } else if (q.contains('trường') || q.contains('đại học')) {
      suggestions.addAll([
        'Đại học Quốc gia Hà Nội',
        'Đại học Bách khoa Hà Nội',
        'Đại học Kinh tế Quốc dân',
      ]);
    } else if (q.contains('cafe') || q.contains('cà phê')) {
      suggestions.addAll([
        'Cafe Cầu Giấy',
        'Highlands Coffee Hà Nội',
        'The Coffee House Hà Nội',
      ]);
    } else if (q.contains('đường') || q.contains('phố') || q.contains('ngõ')) {
      suggestions.addAll([
        'Đường Xuân Thủy Hà Nội',
        'Phố Huế Hà Nội',
        'Đường Nguyễn Trãi Hà Nội',
      ]);
    }

    if (suggestions.isEmpty && q.length <= 4) {
      suggestions.addAll([
        '$keyword Hà Nội',
        '$keyword Cầu Giấy',
        '$keyword Mỹ Đình',
        '$keyword Việt Nam',
      ]);
    }

    final seen = <String>{};

    return suggestions
        .where((s) => seen.add(s.toLowerCase()))
        .take(5)
        .toList();
  }

  List<Marker> _buildRouteMarkers() {
    final markers = <Marker>[];

    if (_startPoint != null && !_isNavigating) {
      markers.add(_labelMarker(_startPoint!, 'A', Colors.green));
    }

    for (int i = 0; i < _stopPoints.length; i++) {
      markers.add(_labelMarker(_stopPoints[i], '${i + 1}', Colors.orange));
    }

    if (_destinationPoint != null) {
      markers.add(_labelMarker(_destinationPoint!, 'B', Colors.red));
    }

    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 52,
          height: 52,
          child: Icon(
            _isNavigating ? Icons.navigation : Icons.my_location,
            color: Colors.blue,
            size: 34,
          ),
        ),
      );
    }

    return markers;
  }

  Marker _labelMarker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 46,
      height: 46,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 3,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
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
            final selected = t.name == _transport.name;

            return GestureDetector(
              onTap: () async {
                setState(() => _transport = t);
                Navigator.pop(context);

                _isNavigating
                    ? await _buildNavigationRoute()
                    : await _buildPreviewRoute();
              },
              child: Card(
                color: selected ? Colors.orange.shade100 : null,
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
            final selected = style.name == _mapStyle.name;

            return ListTile(
              leading: Icon(
                selected ? Icons.check_circle : Icons.map_outlined,
                color: selected ? Colors.green : null,
              ),
              title: Text(style.name),
              onTap: () {
                setState(() => _mapStyle = style);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  void _showInfoMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
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
                _menuTile('Bắt đầu: $_startName', Icons.trip_origin),
                _menuTile(
                  'Điểm dừng: ${_stopNames.isEmpty ? 'Chưa có' : _stopNames.join(' → ')}',
                  Icons.add_location_alt,
                ),
                _menuTile(
                  'Điểm đến: ${_destinationName.isEmpty ? 'Chưa chọn' : _destinationName}',
                  Icons.flag,
                ),
                _menuTile('Phương tiện: ${_transport.name}', Icons.directions),
                _menuTile(
                  'Tuyến xem trước: ${(_plannedDistM / 1000).toStringAsFixed(2)} km',
                  Icons.alt_route,
                ),
                _menuTile('Thời gian: ${_fmtDuration(_plannedDurS)}', Icons.access_time),
                _menuTile(
                  'Trạng thái: ${_isNavigating ? 'Đang chỉ đường' : 'Chưa bắt đầu'}',
                  Icons.navigation,
                ),
                _menuTile(
                  'Còn lại: ${(_remainingDistM / 1000).toStringAsFixed(2)} km',
                  Icons.social_distance,
                ),
                _menuTile(
                  'Thời gian còn lại: ${_fmtDuration(_remainingDurS)}',
                  Icons.timer,
                ),
                _menuTile(
                  'Đã đi thực tế: ${(_totalDistM / 1000).toStringAsFixed(2)} km',
                  Icons.route,
                ),
                _menuTile(
                  'Breadcrumb: ${_breadcrumb.length}/$_maxBreadcrumb điểm',
                  Icons.timeline,
                ),
                if (_isRouting) _menuTile('Đang tính tuyến đường...', Icons.sync),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(String text, IconData icon) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(
          text,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _bottomBtn({
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
            border: Border.all(
              color: Colors.white,
              width: 2.5,
            ),
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
    final active = _searchMode == mode;

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
                _searchMode = mode;
                _showRecent = false;
                _showSuggestions = false;
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

  Widget _searchPanel() {
    final kw = _searchKeyword.trim();
    final quick = _smartSuggestions(kw);
    final hasApiResults = _suggestions.isNotEmpty;
    final hasQuick = quick.isNotEmpty;

    if (kw.isNotEmpty &&
        (_showSuggestions || _isSearching || hasApiResults || hasQuick)) {
      return _SuggestionPanel(
        isSearching: _isSearching,
        apiSuggestions: _suggestions,
        quickSuggestions: quick,
        iconFor: _iconFor,
        subtitleFor: (item) {
          final dn = (item['display_name'] ?? '').toString();
          final title = SearchService.getVietnameseName(item);

          return (dn.trim().isEmpty || dn == title)
              ? 'Nhấn để chọn địa điểm'
              : dn;
        },
        onApiTap: _selectSuggestion,
        onQuickTap: (text) {
          _searchController.text = text;
          _searchLocation(text);
        },
      );
    }

    if (_showRecent && _recentSearches.isNotEmpty) {
      return _RecentPanel(
        items: _recentSearches,
        onTap: _selectRecentSearch,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _gpsChip() {
    final acc = _currentAccuracy;
    final text = acc == null ? 'GPS: đang lấy...' : 'GPS: ±${acc.toStringAsFixed(0)}m';
    final color = acc == null
        ? Colors.grey
        : acc <= 20
        ? const Color(0xFF16A34A)
        : acc <= 50
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rotateToggleButton() {
    if (!_isNavigating) return const SizedBox.shrink();

    return FloatingActionButton.small(
      heroTag: 'rotate_toggle_btn',
      backgroundColor: _autoRotateMap ? const Color(0xFF006B63) : Colors.white,
      foregroundColor: _autoRotateMap ? Colors.white : Colors.black87,
      onPressed: () {
        setState(() {
          _autoRotateMap = !_autoRotateMap;
          if (!_autoRotateMap) _cameraBearing = 0;
        });

        if (_currentLocation != null) {
          try {
            if (_autoRotateMap) {
              _mapController.moveAndRotate(_currentLocation!, 17, _cameraBearing);
            } else {
              _mapController.moveAndRotate(_currentLocation!, 16, 0);
            }
          } catch (_) {}
        }
      },
      child: Icon(_autoRotateMap ? Icons.explore_rounded : Icons.explore_off_rounded),
    );
  }

  Widget _placeholderImage(String title) {
    final text = title.toLowerCase();
    IconData icon;
    Color bg;
    Color fg;

    if (text.contains('sân bay') || text.contains('airport')) {
      icon = Icons.flight_takeoff_rounded;
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0284C7);
    } else if (text.contains('bệnh viện') || text.contains('hospital')) {
      icon = Icons.local_hospital_rounded;
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
    } else if (text.contains('trường') || text.contains('đại học')) {
      icon = Icons.school_rounded;
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
    } else if (text.contains('cafe') ||
        text.contains('cà phê') ||
        text.contains('coffee')) {
      icon = Icons.local_cafe_rounded;
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
    } else if (text.contains('khách sạn') || text.contains('hotel')) {
      icon = Icons.hotel_rounded;
      bg = const Color(0xFFEDE9FE);
      fg = const Color(0xFF7C3AED);
    } else if (text.contains('nhà hàng') ||
        text.contains('quán ăn') ||
        text.contains('restaurant')) {
      icon = Icons.restaurant_rounded;
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFEA580C);
    } else if (text.contains('sân vận động') || text.contains('stadium')) {
      icon = Icons.sports_soccer_rounded;
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF059669);
    } else if (text.contains('cây xăng') || text.contains('xăng')) {
      icon = Icons.local_gas_station_rounded;
      bg = const Color(0xFFF0F9FF);
      fg = const Color(0xFF0369A1);
    } else if (text.contains('siêu thị') ||
        text.contains('chợ') ||
        text.contains('mall')) {
      icon = Icons.shopping_cart_rounded;
      bg = const Color(0xFFFDF4FF);
      fg = const Color(0xFF9333EA);
    } else {
      icon = Icons.location_on_rounded;
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF475569);
    }

    return Container(
      height: 150,
      width: double.infinity,
      color: bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: fg),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeInfoCard() {
    final info = _selectedPlace;
    if (info == null) return const SizedBox.shrink();

    final title = info['title'].toString();
    final address = info['address'].toString();
    final imageUrl = info['imageUrl'].toString();

    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                      imageUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: 700,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;

                        return Container(
                          height: 150,
                          color: Colors.grey.shade100,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                                  : null,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => _placeholderImage(title),
                    )
                        : _placeholderImage(title),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _closePlaceInfo,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_plannedDistM > 0)
                      Text(
                        'Tuyến đường: ${_distanceText(_plannedDistM)} · ${_fmtDuration(_plannedDurS)}',
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _startNavigation,
                            icon: const Icon(Icons.directions),
                            label: const Text('Đến'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saveSelectedPlace,
                            icon: const Icon(Icons.bookmark_add),
                            label: const Text('Lưu'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationHeader() {
    if (!_isNavigating || _destinationPoint == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF006B63),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.straight_rounded,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  _bearingDirectionText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationBottomPanel() {
    if (!_isNavigating || _destinationPoint == null) {
      return const SizedBox.shrink();
    }

    final distance = _remainingDistM > 0 ? _remainingDistM : _plannedDistM;
    final duration = _remainingDurS > 0 ? _remainingDurS : _plannedDurS;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          22,
          18,
          22,
          MediaQuery.of(context).padding.bottom + 18,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(26),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 14,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmtDuration(duration),
                    style: const TextStyle(
                      color: Color(0xFF188038),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_distanceText(distance)} · ${_arrivalTimeText(duration)}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.grey.shade100,
              child: const Icon(
                Icons.alt_route_rounded,
                color: Colors.black87,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            ElevatedButton(
              onPressed: _stopNavigation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Thoát',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _searchHint() {
    switch (_searchMode) {
      case SearchMode.start:
        return 'Nhập điểm bắt đầu...';
      case SearchMode.stop:
        return 'Nhập điểm dừng...';
      case SearchMode.destination:
        return 'Nhập điểm đến...';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLocation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final bottom = media.padding.bottom;

    return GestureDetector(
      onTap: _hideSearchPanels,
      child: Stack(
        children: [
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
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
                  keepBuffer: 4,
                  maxNativeZoom: 19,
                  maxZoom: 20,
                  tileDisplay: const TileDisplay.fadeIn(),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _breadcrumb,
                      strokeWidth: 5,
                      color: Colors.blue.withOpacity(0.25),
                    ),
                  ],
                ),
                if (_routedPath.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routedPath,
                        strokeWidth: 6,
                        color: _isNavigating
                            ? const Color(0xFF3B00FF)
                            : Colors.orange,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    ..._buildRouteMarkers(),
                    ..._savedMarkers,
                  ],
                ),
              ],
            ),
          ),

          if (!_isNavigating)
            Positioned(
              left: 16,
              top: top + 126,
              child: _gpsChip(),
            ),

          if (!_isNavigating)
            Positioned(
              top: top + 12,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _searchHint(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _isSearching
                            ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                            : IconButton(
                          onPressed: () => _searchLocation(_searchController.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                          _showRecent = _searchController.text.trim().isEmpty &&
                              _recentSearches.isNotEmpty;
                          _showSuggestions = false;
                        });
                      },
                      onChanged: (value) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 400),
                              () {
                            if (value.trim().length >= 2) {
                              _loadSuggestions(value);
                            }
                          },
                        );
                      },
                      onSubmitted: _searchLocation,
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

          if (!_isNavigating)
            Positioned(
              top: top + 118,
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
                  child: const Icon(Icons.info_outline_rounded, size: 22),
                ),
              ),
            ),

          if (!_isNavigating)
            Positioned(
              top: top + 170,
              right: 16,
              child: Column(
                children: [
                  _bottomBtn(
                    icon: Icons.directions_car_rounded,
                    color: const Color(0xFF0EA5E9),
                    tooltip: 'Chọn phương tiện',
                    onPressed: _showTransportPicker,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: Icons.map_rounded,
                    color: const Color(0xFF8B5CF6),
                    tooltip: 'Đổi kiểu bản đồ',
                    onPressed: _showStylePicker,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: Icons.bookmark_added_rounded,
                    color: const Color(0xFFEC4899),
                    tooltip: 'Lưu vị trí hiện tại',
                    onPressed: _saveCurrentLocation,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: _followLocation
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_not_fixed_rounded,
                    color: _followLocation
                        ? const Color(0xFF14B8A6)
                        : const Color(0xFF64748B),
                    tooltip: _followLocation ? 'Đang bám vị trí' : 'Bật bám vị trí',
                    onPressed: () {
                      setState(() => _followLocation = !_followLocation);

                      if (_followLocation && _currentLocation != null) {
                        _moveSafely(
                          _currentLocation!,
                          _isNavigating ? 17 : 16,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

          if (_selectedPlace == null && !_isNavigating)
            Positioned(
              left: 16,
              bottom: bottom + 90,
              child: Column(
                children: [
                  _bottomBtn(
                    icon: Icons.navigation_rounded,
                    color: _isNavigating
                        ? Colors.grey.shade400
                        : const Color(0xFF16A34A),
                    tooltip: 'Bắt đầu chỉ đường',
                    onPressed: _isNavigating ? null : _startNavigation,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: Icons.pause_circle_filled_rounded,
                    color: const Color(0xFFF59E0B),
                    tooltip: 'Dừng chỉ đường',
                    onPressed: _stopNavigation,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: Icons.remove_circle_rounded,
                    color: const Color(0xFF6366F1),
                    tooltip: 'Xóa điểm dừng cuối',
                    onPressed: _removeLastStop,
                  ),
                  const SizedBox(height: 10),
                  _bottomBtn(
                    icon: Icons.delete_forever_rounded,
                    color: const Color(0xFFEF4444),
                    tooltip: 'Xóa toàn bộ tuyến',
                    onPressed: _clearRoute,
                  ),
                ],
              ),
            ),

          if (_isNavigating)
            Positioned(
              right: 18,
              bottom: bottom + 160,
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: 'nav_search_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    onPressed: () {
                      setState(() => _isNavigating = false);
                      _startTracking();
                    },
                    child: const Icon(Icons.search, size: 34),
                  ),
                  const SizedBox(height: 14),
                  FloatingActionButton(
                    heroTag: 'nav_sound_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    onPressed: () {
                      setState(() => _voiceEnabled = !_voiceEnabled);
                      if (_voiceEnabled) {
                        _speakNow('Đã bật âm thanh chỉ đường');
                      } else {
                        SoundService.stop();
                        _showSnack('Đã tắt âm thanh chỉ đường');
                      }
                    },
                    child: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off, size: 32),
                  ),
                ],
              ),
            ),

          _placeInfoCard(),
          _navigationHeader(),
          _navigationBottomPanel(),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  final bool isSearching;
  final List<Map<String, dynamic>> apiSuggestions;
  final List<String> quickSuggestions;
  final IconData Function(String) iconFor;
  final String Function(Map<String, dynamic>) subtitleFor;
  final void Function(Map<String, dynamic>) onApiTap;
  final void Function(String) onQuickTap;

  const _SuggestionPanel({
    required this.isSearching,
    required this.apiSuggestions,
    required this.quickSuggestions,
    required this.iconFor,
    required this.subtitleFor,
    required this.onApiTap,
    required this.onQuickTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 330),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            if (isSearching)
              const ListTile(
                dense: true,
                leading: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Đang tìm địa điểm...'),
              ),
            if (!isSearching &&
                apiSuggestions.isEmpty &&
                quickSuggestions.isEmpty)
              const ListTile(
                leading: Icon(Icons.search_off_rounded),
                title: Text('Chưa tìm thấy địa điểm'),
                subtitle: Text('Thử nhập rõ hơn, ví dụ: sân bay Nội Bài'),
              ),
            ...apiSuggestions.map((item) {
              final title = SearchService.getVietnameseName(item);

              return ListTile(
                leading: Icon(
                  iconFor('$title ${subtitleFor(item)}'),
                  color: const Color(0xFF2563EB),
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  subtitleFor(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.north_west_rounded, size: 18),
                onTap: () => onApiTap(item),
              );
            }),
            if (quickSuggestions.isNotEmpty && apiSuggestions.isNotEmpty)
              const Divider(height: 1),
            ...quickSuggestions.map(
                  (text) => ListTile(
                dense: true,
                leading: Icon(
                  iconFor(text),
                  color: const Color(0xFF2563EB),
                ),
                title: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Gợi ý nhanh',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onQuickTap(text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPanel extends StatelessWidget {
  final List<String> items;
  final void Function(String) onTap;

  const _RecentPanel({
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: items
              .map(
                (item) => ListTile(
              dense: true,
              leading: const Icon(Icons.history_rounded),
              title: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.north_west_rounded, size: 18),
              onTap: () => onTap(item),
            ),
          )
              .toList(),
        ),
      ),
    );
  }
}
