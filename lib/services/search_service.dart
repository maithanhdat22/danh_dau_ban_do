import 'dart:convert';
import 'package:http/http.dart' as http;

class SearchService {
  static Future<Map<String, dynamic>?> searchPlace(String query) async {
    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1");

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data.isNotEmpty) return data[0];
    }

    return null;
  }
}