class PlaceMarker {
  final String title;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final double? distanceAtSave;

  const PlaceMarker({
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.distanceAtSave,
  });
}