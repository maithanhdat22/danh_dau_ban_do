import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TripVideoScreen extends StatefulWidget {
  final List<LatLng> points;
  final String title;

  const TripVideoScreen({
    super.key,
    required this.points,
    this.title = 'Video hành trình',
  });

  @override
  State<TripVideoScreen> createState() => _TripVideoScreenState();
}

class _TripVideoScreenState extends State<TripVideoScreen> {
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  Timer? _timer;
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _distanceKm = 0;

  @override
  void initState() {
    super.initState();

    if (widget.points.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitRoute();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fitRoute() {
    try {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: widget.points,
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {}
  }

  void _play() {
    if (widget.points.length < 2) return;

    setState(() {
      _isPlaying = true;
    });

    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(milliseconds: 120),
          (_) {
        if (_currentIndex >= widget.points.length - 1) {
          _pause();
          return;
        }

        final oldPoint = widget.points[_currentIndex];
        final newPoint = widget.points[_currentIndex + 1];

        final addMeter = _distance.as(
          LengthUnit.Meter,
          oldPoint,
          newPoint,
        );

        setState(() {
          _currentIndex++;
          _distanceKm += addMeter / 1000;
        });

        try {
          _mapController.move(
            newPoint,
            13,
          );
        } catch (_) {}
      },
    );
  }

  void _pause() {
    _timer?.cancel();

    setState(() {
      _isPlaying = false;
    });
  }

  void _restart() {
    _timer?.cancel();

    setState(() {
      _currentIndex = 0;
      _distanceKm = 0;
      _isPlaying = false;
    });

    _fitRoute();
  }

  List<LatLng> get _playedPoints {
    if (widget.points.isEmpty) return [];

    return widget.points.sublist(
      0,
      _currentIndex + 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Video hành trình'),
        ),
        body: const Center(
          child: Text(
            'Chưa có đủ dữ liệu hành trình để tạo video.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final currentPoint = widget.points[_currentIndex];
    final progress = _currentIndex / (widget.points.length - 1);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.points.first,
              initialZoom: 12,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.danh_dau_ban_do',
              ),

              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.points,
                    strokeWidth: 5,
                    color: Colors.grey.withOpacity(0.45),
                  ),
                  Polyline(
                    points: _playedPoints,
                    strokeWidth: 7,
                    color: Colors.red,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.points.first,
                    width: 45,
                    height: 45,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 42,
                    ),
                  ),

                  Marker(
                    point: widget.points.last,
                    width: 45,
                    height: 45,
                    child: const Icon(
                      Icons.flag,
                      color: Colors.red,
                      size: 42,
                    ),
                  ),

                  Marker(
                    point: currentPoint,
                    width: 60,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            left: 20,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _controlButton(
                        icon: Icons.replay,
                        label: 'Chạy lại',
                        onTap: _restart,
                      ),

                      _controlButton(
                        icon: _isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        label: _isPlaying ? 'Tạm dừng' : 'Phát',
                        onTap: _isPlaying ? _pause : _play,
                        big: true,
                      ),

                      _controlButton(
                        icon: Icons.fit_screen,
                        label: 'Toàn tuyến',
                        onTap: _fitRoute,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool big = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: big ? 34 : 28,
            backgroundColor: big ? Colors.blue : Colors.grey.shade200,
            child: Icon(
              icon,
              color: big ? Colors.white : Colors.black87,
              size: big ? 36 : 28,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}