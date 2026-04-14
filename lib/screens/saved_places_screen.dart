import 'package:flutter/material.dart';
import '../models/place_marker.dart';

class SavedPlacesScreen extends StatelessWidget {
  final List<PlaceMarker> places;
  final ValueChanged<int> onDelete;

  const SavedPlacesScreen({
    super.key,
    required this.places,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có địa điểm nào được lưu',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: places.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final place = places[index];

        return Card(
          elevation: 3,
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.location_pin),
            ),
            title: Text(place.title),
            subtitle: Text(
              'Lat: ${place.latitude.toStringAsFixed(6)}\n'
                  'Lng: ${place.longitude.toStringAsFixed(6)}\n'
                  'Đã đi: ${((place.distanceAtSave ?? 0) / 1000).toStringAsFixed(2)} km\n'
                  'Tạo lúc: ${place.createdAt}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              onPressed: () => onDelete(index),
              icon: const Icon(Icons.delete, color: Colors.red),
            ),
          ),
        );
      },
    );
  }
}