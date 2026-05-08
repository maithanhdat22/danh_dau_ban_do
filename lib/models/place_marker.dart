import 'dart:convert';

import 'package:latlong2/latlong.dart';

class PlaceMarker {
  final String id;
  final String title;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final double? distanceAtSave;
  final String? transportName;
  final String? description;
  final String? imageUrl;
  final String? address;

  final List<LatLng> routePoints;

  const PlaceMarker({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.distanceAtSave,
    this.transportName,
    this.description,
    this.imageUrl,
    this.address,
    this.routePoints = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toIso8601String(),
      'distanceAtSave': distanceAtSave,
      'transportName': transportName,
      'description': description,
      'imageUrl': imageUrl,
      'address': address,
      'routePoints': routePoints
          .map(
            (p) => {
          'lat': p.latitude,
          'lng': p.longitude,
        },
      )
          .toList(),
    };
  }

  factory PlaceMarker.fromMap(Map<String, dynamic> map) {
    final rawRoutePoints = map['routePoints'];

    return PlaceMarker(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      distanceAtSave: map['distanceAtSave'] != null
          ? (map['distanceAtSave'] as num).toDouble()
          : null,
      transportName: map['transportName'],
      description: map['description'],
      imageUrl: map['imageUrl'],
      address: map['address'],
      routePoints: rawRoutePoints is List
          ? rawRoutePoints
          .map((e) {
        final item = e as Map<String, dynamic>;

        return LatLng(
          (item['lat'] as num).toDouble(),
          (item['lng'] as num).toDouble(),
        );
      })
          .toList()
          : const [],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PlaceMarker.fromJson(String source) {
    return PlaceMarker.fromMap(jsonDecode(source));
  }
}