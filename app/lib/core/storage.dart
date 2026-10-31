import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Datos guardados en el teléfono. Los tokens y el carné van cifrados
/// (flutter_secure_storage); el resto, en preferencias.
class Storage {
  static const _secure = FlutterSecureStorage();

  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _lastLogin = 'last_login';
  static const _lastCard = 'last_card';

  static const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // Tokens

  static Future<String?> accessToken() => _secure.read(key: _accessToken);

  static Future<String?> refreshToken() => _secure.read(key: _refreshToken);

  static Future<void> saveTokens(String access, String refresh) async {
    await _secure.write(key: _accessToken, value: access);
    await _secure.write(key: _refreshToken, value: refresh);
  }

  static Future<void> clearTokens() async {
    await _secure.delete(key: _accessToken);
    await _secure.delete(key: _refreshToken);
  }

  // Usuario recordado (solo en este teléfono). Las versiones anteriores
  // recordaban el carné: se usa hasta el siguiente inicio de sesión.

  static Future<String?> lastLogin() async => await _secure.read(key: _lastLogin) ?? await _secure.read(key: _lastCard);

  static Future<void> saveLastLogin(String? login) async {
    await _secure.delete(key: _lastCard);
    login == null ? await _secure.delete(key: _lastLogin) : await _secure.write(key: _lastLogin, value: login);
  }

  // Preferencias

  static Future<String> apiUrl() async => (await _prefs).getString('api_url') ?? defaultApiUrl;

  static Future<void> setApiUrl(String url) async => (await _prefs).setString('api_url', url);

  static Future<bool> getBool(String key, {bool fallback = false}) async => (await _prefs).getBool(key) ?? fallback;

  static Future<void> setBool(String key, bool value) async => (await _prefs).setBool(key, value);

  static Future<String?> getString(String key) async => (await _prefs).getString(key);

  static Future<void> setString(String key, String? value) async {
    final prefs = await _prefs;
    value == null ? await prefs.remove(key) : await prefs.setString(key, value);
  }

  static Future<Map<String, dynamic>> getJson(String key) async {
    final raw = (await _prefs).getString(key);
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> setJson(String key, Map<String, dynamic> value) async => (await _prefs).setString(key, jsonEncode(value));

  /// Borra lo que pertenece al usuario (al cerrar sesión).
  static Future<void> clearUserData() async {
    await clearTokens();
    final prefs = await _prefs;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('user.')) await prefs.remove(key);
    }
  }
}
