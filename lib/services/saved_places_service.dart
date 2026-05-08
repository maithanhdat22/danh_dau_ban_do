import 'package:shared_preferences/shared_preferences.dart';
import '../models/place_marker.dart';

class SavedPlacesService {
  static const String _key = 'saved_places';

  static Future<List<PlaceMarker>> getPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    return data.map((e) => PlaceMarker.fromJson(e)).toList();
  }

  static Future<void> savePlaces(List<PlaceMarker> places) async {
    final prefs = await SharedPreferences.getInstance();
    final data = places.map((e) => e.toJson()).toList();
    await prefs.setStringList(_key, data);
  }

  static Future<void> addPlace(PlaceMarker place) async {
    final places = await getPlaces();

    final exists = places.any(
          (p) =>
      p.latitude == place.latitude &&
          p.longitude == place.longitude &&
          p.title == place.title,
    );

    if (!exists) {
      places.add(place);
      await savePlaces(places);
    }
  }

  static Future<void> removePlaceAt(int index) async {
    final places = await getPlaces();
    if (index >= 0 && index < places.length) {
      places.removeAt(index);
      await savePlaces(places);
    }
  }
}