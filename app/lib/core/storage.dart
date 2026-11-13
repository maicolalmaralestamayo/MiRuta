import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_url.dart';

/// Datos guardados en el teléfono. Los tokens y el usuario recordado van
/// cifrados (flutter_secure_storage); el resto, en preferencias.
class Storage {
  static const _secure = FlutterSecureStorage();

  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _lastLogin = 'last_login';
  static const _lastCard = 'last_card';

  /// Dirección del servidor con la que viene la app (--dart-define=API_URL=…,
  /// opcional). El usuario la puede cambiar con el botón «Servidor»
  /// (docs/05-app.md §5.2).
  static const defaultApiUrl = String.fromEnvironment('API_URL');

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

  /// Dirección de la API, o cadena vacía si aún no se ha indicado.
  static Future<String> apiUrl() async {
    final saved = (await _prefs).getString('api_url');
    if (saved != null) return saved;
    return ServerUrl.fromInput(defaultApiUrl) ?? '';
  }

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

  /// La app está abierta en primer plano (docs/11 §11.56): la tarea en
  /// segundo plano no consulta mientras tanto, para no repetir en el
  /// teléfono las notificaciones que la app ya muestra dentro.
  static Future<void> setForeground(bool value) async {
    final prefs = await _prefs;
    value ? await prefs.setInt('app.foreground_at', DateTime.now().millisecondsSinceEpoch) : await prefs.remove('app.foreground_at');
  }

  /// Si la app estuvo en primer plano en los últimos [within] (lo lee la tarea en segundo plano).
  static Future<bool> isForeground({Duration within = const Duration(minutes: 3)}) async {
    final prefs = await _prefs;
    await prefs.reload();
    final at = prefs.getInt('app.foreground_at');
    return at != null && DateTime.now().millisecondsSinceEpoch - at < within.inMilliseconds;
  }

  /// Borra lo que pertenece al usuario (al cerrar sesión).
  static Future<void> clearUserData() async {
    await clearTokens();
    final prefs = await _prefs;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('user.')) await prefs.remove(key);
    }
  }
}
