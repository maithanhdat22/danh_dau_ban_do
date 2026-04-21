import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static String? _initializationErrorMessage;

  static bool get isConfigured => DefaultFirebaseOptions.isConfigured;
  static bool get isReady => isConfigured && _initializationErrorMessage == null;
  static String? get initializationErrorMessage =>
      _initializationErrorMessage ?? DefaultFirebaseOptions.configurationIssue;

  static Future<void> initializeFirebase() async {
    _initializationErrorMessage = DefaultFirebaseOptions.configurationIssue;

    if (_initializationErrorMessage != null || Firebase.apps.isNotEmpty) {
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initializationErrorMessage = null;
    } on FirebaseException catch (error) {
      _initializationErrorMessage =
          error.message ?? 'Khoi tao Firebase that bai.';
    } catch (_) {
      _initializationErrorMessage = 'Khong the khoi tao Firebase.';
    }
  }

  static AppUser? getCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _mapFirebaseUser(user);
  }

  static Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    _ensureAvailable();

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'Dang nhap that bai. Khong nhan duoc thong tin nguoi dung.',
        );
      }

      return _mapFirebaseUser(user);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_mapFirebaseAuthError(error));
    }
  }

  static Future<AppUser> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _ensureAvailable();

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'Dang ky that bai. Khong nhan duoc thong tin nguoi dung.',
        );
      }

      await user.updateDisplayName(fullName.trim());
      await user.reload();

      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) {
        throw const AuthException(
          'Dang ky xong nhung khong doc lai duoc ho so nguoi dung.',
        );
      }

      return _mapFirebaseUser(refreshedUser);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_mapFirebaseAuthError(error));
    }
  }

  static Future<void> logout() async {
    if (!isReady) return;
    await FirebaseAuth.instance.signOut();
  }

  static void _ensureAvailable() {
    final configurationIssue = DefaultFirebaseOptions.configurationIssue;
    if (configurationIssue != null) {
      throw AuthException(configurationIssue);
    }

    if (_initializationErrorMessage != null) {
      throw AuthException(_initializationErrorMessage!);
    }
  }

  static AppUser _mapFirebaseUser(User user) {
    final email = user.email?.trim() ?? '';
    final username = _usernameFromEmail(email);
    final fullName = (user.displayName ?? '').trim();

    return AppUser(
      uid: user.uid,
      username: username,
      fullName: fullName.isEmpty ? username : fullName,
      email: email,
    );
  }

  static String _usernameFromEmail(String email) {
    if (email.isEmpty) return 'user';
    return email.split('@').first;
  }

  static String _mapFirebaseAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Email khong hop le.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Sai email hoac mat khau.';
      case 'email-already-in-use':
        return 'Email nay da duoc su dung.';
      case 'weak-password':
        return 'Mat khau qua yeu. Hay dung it nhat 6 ky tu.';
      case 'too-many-requests':
        return 'Ban thu dang nhap qua nhieu lan. Hay doi mot luc roi thu lai.';
      case 'network-request-failed':
        return 'Ket noi mang that bai.';
      default:
        return error.message ?? 'Xac thuc that bai.';
    }
  }
}
