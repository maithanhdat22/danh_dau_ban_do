import 'package:flutter/material.dart';

enum BaseMapType {
  osmStandard,
  openTopo,
}

class AppMapTheme {
  final String name;
  final Color routeColor;
  final Color currentMarkerColor;
  final Color savedMarkerColor;
  final Color infoCardColor;
  final Color infoTextColor;
  final Color fabColor;

  const AppMapTheme({
    required this.name,
    required this.routeColor,
    required this.currentMarkerColor,
    required this.savedMarkerColor,
    required this.infoCardColor,
    required this.infoTextColor,
    required this.fabColor,
  });
}

class MapStyleOption {
  final String name;
  final BaseMapType baseMapType;
  final AppMapTheme theme;

  const MapStyleOption({
    required this.name,
    required this.baseMapType,
    required this.theme,
  });
}

class MapStylePresets {
  static const AppMapTheme classicTheme = AppMapTheme(
    name: 'Classic',
    routeColor: Colors.blue,
    currentMarkerColor: Colors.blue,
    savedMarkerColor: Colors.red,
    infoCardColor: Colors.white,
    infoTextColor: Colors.black87,
    fabColor: Colors.blue,
  );

  static const AppMapTheme forestTheme = AppMapTheme(
    name: 'Forest',
    routeColor: Colors.green,
    currentMarkerColor: Colors.green,
    savedMarkerColor: Colors.brown,
    infoCardColor: Color(0xFFF1F8E9),
    infoTextColor: Color(0xFF1B5E20),
    fabColor: Colors.green,
  );

  static const AppMapTheme neonTheme = AppMapTheme(
    name: 'Neon',
    routeColor: Colors.purple,
    currentMarkerColor: Colors.cyan,
    savedMarkerColor: Colors.pink,
    infoCardColor: Color(0xFF111827),
    infoTextColor: Colors.white,
    fabColor: Colors.deepPurple,
  );

  static const List<MapStyleOption> presets = [
    MapStyleOption(
      name: 'OSM Classic',
      baseMapType: BaseMapType.osmStandard,
      theme: classicTheme,
    ),
    MapStyleOption(
      name: 'Topo Forest',
      baseMapType: BaseMapType.openTopo,
      theme: forestTheme,
    ),
    MapStyleOption(
      name: 'OSM Neon',
      baseMapType: BaseMapType.osmStandard,
      theme: neonTheme,
    ),
  ];
}