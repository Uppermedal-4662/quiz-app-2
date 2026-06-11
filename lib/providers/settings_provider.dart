import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _keyDarkMode = 'isDarkMode';
  static const String _keyGamification = 'enableGamification';
  static const String _keyHaptics = 'enableHaptics';
  static const String _keyTTS = 'enableTTS';

  bool _isDarkMode = false;
  bool _enableGamification = true;
  bool _enableHaptics = true;
  bool _enableTTS = false;

  bool get isDarkMode => _isDarkMode;
  bool get enableGamification => _enableGamification;
  bool get enableHaptics => _enableHaptics;
  bool get enableTTS => _enableTTS;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_keyDarkMode) ?? false;
    _enableGamification = prefs.getBool(_keyGamification) ?? true;
    _enableHaptics = prefs.getBool(_keyHaptics) ?? true;
    _enableTTS = prefs.getBool(_keyTTS) ?? false;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
    notifyListeners();
  }

  Future<void> setGamification(bool value) async {
    _enableGamification = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGamification, value);
    notifyListeners();
  }

  Future<void> setHaptics(bool value) async {
    _enableHaptics = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHaptics, value);
    notifyListeners();
  }

  Future<void> setTTS(bool value) async {
    _enableTTS = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTTS, value);
    notifyListeners();
  }
}
