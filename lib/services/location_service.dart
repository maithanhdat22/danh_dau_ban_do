import 'package:geolocator/geolocator.dart';

class LocationService {
  // FIX: Cache instance SharedPreferences-style — permission không hỏi lại
  static bool _permissionGranted = false;

  /// Kiểm tra và xin quyền một lần duy nhất.
  static Future<bool> ensurePermission() async {
    if (_permissionGranted) return true;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    _permissionGranted = true;
    return true;
  }

  /// Lấy vị trí hiện tại một lần (dùng khi khởi động).
  static Future<Position?> getCurrentLocation() async {
    final ok = await ensurePermission();
    if (!ok) return null;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high, // FIX: bestForNavigation quá tốn pin cho lần đầu
      timeLimit: const Duration(seconds: 15),
    );

    if (position.accuracy > 50) return null;
    return position;
  }

  /// FIX: Stream GPS thay vì Timer.periodic + getCurrentLocation.
  /// distanceFilter = 5m → chỉ emit khi thực sự di chuyển, không spam.
  /// accuracy = high thay bestForNavigation → tiết kiệm pin hơn.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // FIX: 3→5m, giảm tần suất emit khi đứng yên
      ),
    ).where((position) => position.accuracy <= 50);
  }

  /// Stream cho chế độ dẫn đường — chính xác hơn, cập nhật nhiều hơn.
  static Stream<Position> getNavigationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).where((position) => position.accuracy <= 30);
  }
}