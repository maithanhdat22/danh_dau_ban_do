import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';

class AuthService {
  static const String _usernameKey = 'saved_username';
  static const String _passwordKey = 'saved_password';
  static const String _fullNameKey = 'saved_full_name';
  static const String _emailKey = 'saved_email';

  static Future<void> seedDefaultUserIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final username = prefs.getString(_usernameKey);
    if (username != null && username.isNotEmpty) return;

    await prefs.setString(_usernameKey, 'admin');
    await prefs.setString(_passwordKey, '123456');
    await prefs.setString(_fullNameKey, 'Administrator');
    await prefs.setString(_emailKey, 'admin@gmail.com');
  }

  static Future<bool> register(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();

    final oldUsername = prefs.getString(_usernameKey);
    if (oldUsername != null && oldUsername.isNotEmpty) {
      return false;
    }

    await prefs.setString(_usernameKey, user.username);
    await prefs.setString(_passwordKey, user.password);
    await prefs.setString(_fullNameKey, user.fullName);
    await prefs.setString(_emailKey, user.email);

    return true;
  }

  static Future<AppUser?> login({
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final savedUsername = prefs.getString(_usernameKey);
    final savedPassword = prefs.getString(_passwordKey);

    if (savedUsername == username && savedPassword == password) {
      return AppUser(
        username: savedUsername ?? '',
        password: savedPassword ?? '',
        fullName: prefs.getString(_fullNameKey) ?? '',
        email: prefs.getString(_emailKey) ?? '',
      );
    }

    return null;
  }

  static Future<AppUser?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();

    final username = prefs.getString(_usernameKey);
    final password = prefs.getString(_passwordKey);

    if (username == null || password == null) return null;

    return AppUser(
      username: username,
      password: password,
      fullName: prefs.getString(_fullNameKey) ?? '',
      email: prefs.getString(_emailKey) ?? '',
    );
  }

  static Future<void> updateUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, user.username);
    await prefs.setString(_passwordKey, user.password);
    await prefs.setString(_fullNameKey, user.fullName);
    await prefs.setString(_emailKey, user.email);
  }
}