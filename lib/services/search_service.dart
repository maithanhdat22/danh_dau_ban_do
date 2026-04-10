import 'dart:convert';
import 'package:http/http.dart' as http;

class SearchService {
  static Future<Map<String, dynamic>?> searchPlace(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'travel-map-app/1.0',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      return data.first as Map<String, dynamic>;
    }

    return null;
  }
}