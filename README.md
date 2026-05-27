# Travel Map GPS

Travel Map GPS là ứng dụng Flutter dùng để tạo hành trình trên bản đồ, tìm kiếm địa điểm, xem tuyến đường, mô phỏng quá trình di chuyển và lưu lại điểm đến yêu thích. Ứng dụng có đăng nhập Firebase, lưu dữ liệu địa điểm cục bộ và hỗ trợ gắn ảnh cá nhân cho từng địa điểm đã lưu.

## Tính năng chính

- Đăng ký, đăng nhập và khôi phục phiên người dùng bằng Firebase Authentication.
- Bản đồ tương tác bằng `flutter_map` với lớp nền OpenStreetMap và OpenTopoMap.
- Tìm kiếm địa điểm bằng Nominatim, ưu tiên kết quả tại Việt Nam và tên tiếng Việt khi có.
- Tạo hành trình gồm điểm đi, nhiều điểm dừng và điểm đến.
- Chạm trực tiếp lên bản đồ để thêm hoặc đổi điểm theo chế độ đang chọn.
- Tính tuyến bằng OSRM cho đi bộ, xe đạp và các phương tiện đi theo đường bộ.
- Có tuyến xem trước dạng đường thẳng khi không lấy được tuyến mạng hoặc khi chọn máy bay.
- Chọn phương tiện: đi bộ, xe đạp, xe máy, ô tô, tàu hỏa, máy bay.
- Hiển thị khoảng cách, thời gian ước tính và animation phương tiện chạy theo tuyến.
- Đổi kiểu bản đồ: Cơ bản, Địa hình, Tối giản.
- Lưu điểm đến vào danh sách địa điểm đã lưu.
- Quản lý địa điểm đã lưu: xem thông tin, tọa độ, mini map, xóa địa điểm và gắn ảnh từ thư viện.
- Màn hình tài khoản hiển thị tên đăng nhập, email, họ tên và đăng xuất.

## Công nghệ sử dụng

- Flutter 3.41.9, Dart 3.11.x
- Firebase Core và Firebase Authentication
- `flutter_map` và `latlong2`
- OpenStreetMap / OpenTopoMap tile servers
- Nominatim API cho tìm kiếm địa điểm
- OSRM public API cho tuyến đường
- `shared_preferences` để lưu danh sách địa điểm
- `image_picker`, `path_provider`, `path` để chọn và lưu ảnh địa điểm
- `geolocator` và `flutter_tts` đã có service sẵn trong code để mở rộng GPS/đọc giọng nói

## Cấu trúc thư mục

```text
lib/
  main.dart                     # Khởi tạo Firebase và chạy ứng dụng
  firebase_options.dart          # Cấu hình Firebase theo nền tảng
  models/                        # AppUser, PlaceMarker, lựa chọn bản đồ/phương tiện
  screens/                       # Login, Register, Dashboard, Map tab, Saved places, Profile
  services/                      # Auth, tìm kiếm, tuyến đường, lưu địa điểm, GPS, TTS
  widgets/
    map_widget.dart              # Màn bản đồ và trình tạo hành trình chính
    app_snack_bar.dart           # SnackBar dùng chung
assets/
  icon.png                       # Icon ứng dụng
```

## Yêu cầu môi trường

- Flutter SDK tương thích Dart `>=3.11.3 <4.0.0`
- Android Studio hoặc VS Code có Flutter plugin
- Thiết bị Android/emulator để chạy cấu hình hiện tại
- Internet để tải map tiles, tìm kiếm địa điểm, lấy tuyến đường và xác thực Firebase

Firebase hiện đã có cấu hình Android trong `lib/firebase_options.dart` và `android/app/google-services.json`. iOS dùng cấu hình native qua `ios/Runner/GoogleService-Info.plist`. Nếu đổi Firebase project hoặc chạy nền tảng khác, hãy cấu hình lại bằng FlutterFire CLI.

## Cài đặt và chạy

1. Cài dependency:

```bash
flutter pub get
```

2. Kiểm tra thiết bị:

```bash
flutter devices
```

3. Chạy ứng dụng:

```bash
flutter run
```

Nếu muốn chỉ định thiết bị Android:

```bash
flutter run -d android
```

## Kiểm thử

Chạy test hiện có:

```bash
flutter test
```

Test hiện tại kiểm tra ứng dụng boot được tới màn đăng nhập `Đăng nhập Travel Map GPS`.

## Build Android

Build APK debug/release theo cấu hình Flutter:

```bash
flutter build apk
```

Build app bundle để phát hành:

```bash
flutter build appbundle
```

Trong `android/app/build.gradle.kts`, app đang dùng:

- `applicationId`: `com.example.ban_do`
- `namespace`: `com.example.ban_do`
- `targetSdk`: `33`
- `version`: lấy từ `pubspec.yaml` (`1.0.0+2`)

Release hiện vẫn dùng debug signing config, cần thay bằng keystore thật trước khi phát hành chính thức.

## Quyền và dữ liệu

Android đã khai báo:

- `INTERNET`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`

iOS đã khai báo mô tả quyền:

- `NSLocationWhenInUseUsageDescription`
- `NSPhotoLibraryUsageDescription`

Dữ liệu tài khoản được xử lý qua Firebase Authentication. Danh sách địa điểm đã lưu được lưu cục bộ bằng `shared_preferences`. Ảnh người dùng chọn cho địa điểm được copy vào thư mục documents của ứng dụng, trong thư mục `saved_images`.

## Ghi chú phát triển

- `MapWidget` là nơi xử lý chính cho tìm kiếm địa điểm, tạo waypoint, gọi OSRM, vẽ polyline, marker và animation phương tiện.
- `LocationService` đã có logic xin quyền vị trí, lấy vị trí hiện tại và stream GPS, nhưng màn bản đồ hiện tại chưa gọi trực tiếp service này.
- `SoundService` đã cấu hình TTS tiếng Việt, có thể dùng để đọc chỉ dẫn nếu bổ sung tính năng dẫn đường từng bước.
- Public API của Nominatim, OSRM và các tile server có giới hạn sử dụng. Khi phát hành thực tế, nên cấu hình endpoint riêng hoặc dịch vụ bản đồ có quota rõ ràng.

## Chính sách riêng tư

Xem chi tiết tại [PRIVACY_POLICY.md](PRIVACY_POLICY.md).
