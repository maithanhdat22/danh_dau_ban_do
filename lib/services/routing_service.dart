import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceInMeters;
  final double durationInSeconds;

  const RouteResult({
    required this.points,
    required this.distanceInMeters,
    required this.durationInSeconds,
  });
}

class RoutingService {
  static String _profileFromTransport(String? transportName) {
    final name = (transportName ?? '').toLowerCase();

    if (name.contains('đi bộ')) return 'foot';
    if (name.contains('xe đạp')) return 'bike';

    return 'driving';
  }

  static Future<RouteResult?> getRoute({
    required List<LatLng> waypoints,
    String? transportName,
  }) async {
    if (waypoints.length < 2) return null;

    final profile = _profileFromTransport(transportName);
    final coordinates = waypoints
        .map((e) => '${e.longitude},${e.latitude}')
        .join(';');

    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/$profile/$coordinates'
          '?overview=full&geometries=geojson&steps=false',
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') return null;

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final firstRoute = routes.first as Map<String, dynamic>;
    final geometry = firstRoute['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;

    final points = coords.map((item) {
      final pair = item as List<dynamic>;
      return LatLng(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
    }).toList();

    return RouteResult(
      points: points,
      distanceInMeters: (firstRoute['distance'] as num).toDouble(),
      durationInSeconds: (firstRoute['duration'] as num).toDouble(),
    );
  }
}