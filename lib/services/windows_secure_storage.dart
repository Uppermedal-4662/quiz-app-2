import 'package:shared_preferences/shared_preferences.dart';

/// A simplified secure storage for Windows using SharedPreferences.
class WindowsSecureStorage {
  static Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}
