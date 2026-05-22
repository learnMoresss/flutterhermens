import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/app_config.dart';
import '../../shared/models/user_session.dart';

class AppStorage {
  AppStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _configKey = 'app_config';
  static const _sessionKey = 'user_session';
  static const _autoYoloKey = 'chat_auto_yolo_prefix';
  static const _createAppModeKey = 'chat_create_app_mode';
  static const _themeModeKey = 'app_theme_mode';
  static const _lastChatSessionIdKey = 'last_chat_session_id';
  static const _lastChatSessionTitleKey = 'last_chat_session_title';

  Future<AppConfig> loadConfig() async {
    final raw = _prefs.getString(_configKey);
    if (raw == null) return AppConfig.empty;
    return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveConfig(AppConfig config) async {
    await _prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<void> clearConfig() async {
    await _prefs.remove(_configKey);
    await _prefs.remove('use_mock_api');
  }

  Future<UserSession> loadSession() async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return UserSession.empty;
    return UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSession(UserSession session) async {
    await _prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() async {
    await _prefs.remove(_sessionKey);
  }

  bool get autoYoloPrefix => _prefs.getBool(_autoYoloKey) ?? false;

  Future<void> setAutoYoloPrefix(bool value) async {
    await _prefs.setBool(_autoYoloKey, value);
  }

  bool get createAppMode => _prefs.getBool(_createAppModeKey) ?? false;

  Future<void> setCreateAppMode(bool value) async {
    await _prefs.setBool(_createAppModeKey, value);
  }

  ThemeMode loadThemeMode() {
    final raw = _prefs.getString(_themeModeKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String? get lastChatSessionId => _prefs.getString(_lastChatSessionIdKey);

  String? get lastChatSessionTitle => _prefs.getString(_lastChatSessionTitleKey);

  Future<void> saveLastChatSession({required String id, String? title}) async {
    await _prefs.setString(_lastChatSessionIdKey, id);
    if (title != null && title.trim().isNotEmpty) {
      await _prefs.setString(_lastChatSessionTitleKey, title.trim());
    }
  }

  Future<void> clearLastChatSession() async {
    await _prefs.remove(_lastChatSessionIdKey);
    await _prefs.remove(_lastChatSessionTitleKey);
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_themeModeKey, v);
  }
}
