import 'dart:convert';
import 'package:http/http.dart' as http;

class SearchService {
  static const Map<String, String> _headers = {
    'User-Agent': 'travel-map-app/1.0',
    'Accept': 'application/json',
    'Accept-Language': 'vi,en;q=0.8',
  };

  // ─── Cache ảnh để không gọi API lại ───────────────────────────────────────
  static final Map<String, String> _imageCache = {};

  // ══════════════════════════════════════════════════════════════════════════
  // Search
  // ══════════════════════════════════════════════════════════════════════════

  static String _smartQuery(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return query;
    if (q.contains('sân bay')) return '$query airport';
    if (q.contains('sân vận động') || q.contains('sân bóng')) return '$query stadium';
    if (q.contains('bệnh viện')) return '$query hospital';
    if (q.contains('trường') || q.contains('đại học')) return '$query university';
    if (q.contains('cafe') || q.contains('cà phê')) return '$query cafe';
    if (q.contains('khách sạn')) return '$query hotel';
    return query;
  }

  static Future<List<Map<String, dynamic>>> _requestSearch(
      String query, {
        int limit = 10,
        bool vietnamOnly = true,
      }) async {
    final params = {
      'q': query,
      'format': 'json',
      'limit': '$limit',
      'addressdetails': '1',
      'namedetails': '1',
    };

    if (vietnamOnly) params['countrycodes'] = 'vn';

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>?> searchPlace(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return null;

    var results = await _requestSearch(_smartQuery(keyword));
    if (results.isEmpty) results = await _requestSearch(keyword);
    if (results.isEmpty) results = await _requestSearch(keyword, vietnamOnly: false);
    if (results.isEmpty) return null;

    return results.first;
  }

  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return [];

    var results = await _requestSearch(_smartQuery(keyword));
    if (results.isEmpty) results = await _requestSearch(keyword);
    if (results.isEmpty) results = await _requestSearch(keyword, vietnamOnly: false);

    return results;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Lấy ảnh địa điểm — Wikimedia (không cần API key)
  // ══════════════════════════════════════════════════════════════════════════

  /// Lấy URL ảnh thật từ Wikipedia dựa theo tên địa điểm.
  /// Có cache → không gọi lại nếu đã fetch rồi.
  static Future<String?> fetchPlaceImage(String placeName) async {
    final key = placeName.trim().toLowerCase();
    if (key.isEmpty) return null;

    // Trả về cache nếu có
    if (_imageCache.containsKey(key)) {
      final cached = _imageCache[key]!;
      return cached.isEmpty ? null : cached;
    }

    try {
      // Bước 1: Tìm trang Wikipedia theo tên
      final searchUri = Uri.parse(
        'https://vi.wikipedia.org/w/api.php'
            '?action=query'
            '&list=search'
            '&srsearch=${Uri.encodeComponent(placeName)}'
            '&format=json'
            '&srlimit=1',
      );

      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (searchRes.statusCode != 200) {
        _imageCache[key] = '';
        return null;
      }

      final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final searchList =
          (searchData['query']?['search'] as List?) ?? [];

      if (searchList.isEmpty) {
        // Thử Wikipedia tiếng Anh nếu tiếng Việt không có
        return await _fetchFromEnWiki(placeName, key);
      }

      final pageTitle = searchList.first['title'].toString();
      return await _fetchImageByTitle(pageTitle, key);
    } catch (_) {
      _imageCache[key] = '';
      return null;
    }
  }

  /// Lấy ảnh từ Wikipedia tiếng Anh (fallback)
  static Future<String?> _fetchFromEnWiki(String placeName, String cacheKey) async {
    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php'
            '?action=query'
            '&list=search'
            '&srsearch=${Uri.encodeComponent(placeName)}'
            '&format=json'
            '&srlimit=1',
      );

      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) {
        _imageCache[cacheKey] = '';
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['query']?['search'] as List?) ?? [];

      if (list.isEmpty) {
        _imageCache[cacheKey] = '';
        return null;
      }

      final title = list.first['title'].toString();
      return await _fetchImageByTitle(title, cacheKey, lang: 'en');
    } catch (_) {
      _imageCache[cacheKey] = '';
      return null;
    }
  }

  /// Lấy URL ảnh thumbnail từ tên trang Wikipedia
  static Future<String?> _fetchImageByTitle(
      String pageTitle,
      String cacheKey, {
        String lang = 'vi',
      }) async {
    try {
      final uri = Uri.parse(
        'https://$lang.wikipedia.org/w/api.php'
            '?action=query'
            '&titles=${Uri.encodeComponent(pageTitle)}'
            '&prop=pageimages'
            '&format=json'
            '&pithumbsize=700',
      );

      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) {
        _imageCache[cacheKey] = '';
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pages = data['query']?['pages'] as Map<String, dynamic>?;

      if (pages == null) {
        _imageCache[cacheKey] = '';
        return null;
      }

      for (final page in pages.values) {
        final thumb = page['thumbnail'];
        if (thumb != null) {
          final url = thumb['source'].toString();
          _imageCache[cacheKey] = url;
          return url;
        }
      }

      _imageCache[cacheKey] = '';
      return null;
    } catch (_) {
      _imageCache[cacheKey] = '';
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tên tiếng Việt
  // ══════════════════════════════════════════════════════════════════════════

  static String getVietnameseName(Map<String, dynamic> item) {
    final namedetails = item['namedetails'];

    if (namedetails is Map) {
      final nameVi = namedetails['name:vi'];
      final name = namedetails['name'];

      if (nameVi != null && nameVi.toString().trim().isNotEmpty) {
        return nameVi.toString();
      }
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString();
      }
    }

    return (item['display_name'] ?? 'Địa điểm').toString();
  }
}