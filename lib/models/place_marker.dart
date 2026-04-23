import 'dart:convert';

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
    };
  }

  factory PlaceMarker.fromMap(Map<String, dynamic> map) {
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
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PlaceMarker.fromJson(String source) {
    return PlaceMarker.fromMap(jsonDecode(source));
  }
}