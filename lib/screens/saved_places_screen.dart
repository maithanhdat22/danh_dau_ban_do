import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/place_marker.dart';

class SavedPlacesScreen extends StatelessWidget {
  final List<PlaceMarker> places;
  final ValueChanged<int> onDelete;
  final void Function(int index, String imagePath) onImageSelected;

  const SavedPlacesScreen({
    super.key,
    required this.places,
    required this.onDelete,
    required this.onImageSelected,
  });

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickImage(int index) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (image == null) return;
    onImageSelected(index, image.path);
  }

  Widget _buildPlaceImage(PlaceMarker place) {
    final imagePath = place.imageUrl;
    if (imagePath == null || imagePath.isEmpty) {
      return Container(
        height: 180,
        width: double.infinity,
        color: const Color(0xFFEFF6FF),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 42, color: Color(0xFF2563EB)),
            SizedBox(height: 8),
            Text(
              'Chưa có hình ảnh',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Image.file(
      File(imagePath),
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 180,
          width: double.infinity,
          color: const Color(0xFFF1F5F9),
          child: const Center(child: Text('Không mở được hình ảnh')),
        );
      },
    );
  }

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
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final place = places[index];

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPlaceImage(place),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: SizedBox(
                        width: 118,
                        height: 86,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                          ),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter:
                                  LatLng(place.latitude, place.longitude),
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.example.danh_dau_ban_do',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      place.latitude,
                                      place.longitude,
                                    ),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_pin,
                                      color: Colors.red,
                                      size: 32,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: FilledButton.icon(
                        onPressed: () => _pickImage(index),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          place.imageUrl == null || place.imageUrl!.isEmpty
                              ? 'Thêm ảnh'
                              : 'Đổi ảnh',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xE62563EB),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (place.imageUrl == null || place.imageUrl!.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(index),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Tải hình ảnh của bạn lên'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE8F0FE),
                      child: Icon(
                        Icons.location_pin,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        place.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => onDelete(index),
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (place.address != null && place.address!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Địa chỉ: ${place.address}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    if (place.description != null &&
                        place.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Mô tả: ${place.description}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    Text(
                      'Lat: ${place.latitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Lng: ${place.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Đã đi: ${((place.distanceAtSave ?? 0) / 1000).toStringAsFixed(2)} km',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Phương tiện: ${place.transportName ?? 'Không xác định'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Lưu lúc: ${_formatDate(place.createdAt)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
