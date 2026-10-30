import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PIN propio de la app (opcional), igual en cualquier teléfono: no depende
/// de la huella ni del bloqueo de pantalla. Se guarda solo su huella SHA-256
/// con sal, cifrada en el almacenamiento seguro.
class AppPin {
  static const _storage = FlutterSecureStorage();
  static const _key = 'app_pin';
  static const minLength = 4;
  static const maxLength = 6;

  /// Intentos fallidos antes de cerrar la sesión.
  static const maxAttempts = 5;

  static Future<bool> isEnabled() async => await _storage.read(key: _key) != null;

  static Future<void> set(String pin) async {
    final salt = base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await _storage.write(key: _key, value: '$salt:${_hash(salt, pin)}');
  }

  static Future<void> remove() => _storage.delete(key: _key);

  static Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return true;
    final parts = stored.split(':');
    return parts.length == 2 && _hash(parts[0], pin) == parts[1];
  }

  static bool isValidFormat(String pin) => RegExp('^\\d{$minLength,$maxLength}\$').hasMatch(pin);

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt$pin')).toString();
}
