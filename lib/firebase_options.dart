import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Nền tảng này chưa được cấu hình Firebase. Hãy dùng flutterfire configure.',
        );
    }
  }

  static bool get isCurrentPlatformSupported => _currentPlatformOrNull != null;

  static bool get isConfigured {
    final options = _currentPlatformOrNull;
    if (options == null) return false;

    return !_containsPlaceholder(options.apiKey) &&
        !_containsPlaceholder(options.appId) &&
        !_containsPlaceholder(options.messagingSenderId) &&
        !_containsPlaceholder(options.projectId);
  }

  static String get currentPlatformName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  static String? get configurationIssue {
    if (!isCurrentPlatformSupported) {
      return 'Firebase hiện mới được cấu hình cho Android. '
          'Nếu bạn muốn chạy trên $currentPlatformName, hãy thêm cấu hình bằng flutterfire configure.';
    }

    if (isConfigured) return null;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Firebase cho iOS chưa đủ thông tin. '
          'Hãy thêm GoogleService-Info.plist và cập nhật giá trị thật trong lib/firebase_options.dart.';
    }

    return 'Firebase chưa được cấu hình đầy đủ cho $currentPlatformName.';
  }

  static FirebaseOptions? get _currentPlatformOrNull {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return null;
    }
  }

  static bool _containsPlaceholder(String value) {
    return value.isEmpty ||
        value.contains('YOUR_') ||
        value.contains('your-') ||
        value == '1234567890' ||
        value == 'YOUR_ANDROID_APP_ID' ||
        value == 'YOUR_IOS_APP_ID';
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCtnQQwxFvHwwtGlTHCkfvCciSklWF3G-Y',
    appId: '1:346863270119:android:db97a3053fd312ace5ca42',
    messagingSenderId: '346863270119',
    projectId: 'bandodichuyen',
    storageBucket: 'bandodichuyen.firebasestorage.app',
    databaseURL:
        'https://bandodichuyen-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: '1234567890',
    projectId: 'your-project-id',
    iosBundleId: 'com.example.ban_do',
    storageBucket: 'your-project-id.firebasestorage.app',
  );
}
