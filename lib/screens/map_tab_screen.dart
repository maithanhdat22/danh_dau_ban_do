import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/place_marker.dart';
import '../widgets/map_widget.dart';

class MapTabScreen extends StatelessWidget {
  final AppUser user;
  final ValueChanged<PlaceMarker> onPlaceSaved;

  const MapTabScreen({
    super.key,
    required this.user,
    required this.onPlaceSaved,
  });

  @override
  Widget build(BuildContext context) {
    return MapWidget(
      currentUsername: user.username,
      onPlaceSaved: onPlaceSaved,
    );
  }
}