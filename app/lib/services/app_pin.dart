import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PIN propio de la app (opcional), igual en cualquier teléfono: no depende
/// de la huella ni del bloqueo de pantalla.
///
/// Se guarda solo un hash lento (PBKDF2-HMAC-SHA256 con sal y muchas
/// iteraciones) en el almacenamiento seguro: aunque alguien extrajera los
/// datos del teléfono, probar los PIN uno a uno sería muy lento
/// (docs/08-version-2.md §8.4).
class AppPin {
  static const _storage = FlutterSecureStorage();
  static const _key = 'app_pin';
  static const minLength = 4;
  static const maxLength = 6;

  /// Iteraciones de PBKDF2 (en un teléfono normal tarda menos de un segundo).
  static const iterations = 60000;

  /// Intentos fallidos antes de cerrar la sesión.
  static const maxAttempts = 5;

  static Future<bool> isEnabled() async => await _storage.read(key: _key) != null;

  static Future<void> set(String pin) async {
    final salt = base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final hash = await compute(_pbkdf2Isolate, [pin, salt, iterations]);
    await _storage.write(key: _key, value: 'pbkdf2\$$iterations\$$salt\$$hash');
  }

  static Future<void> remove() => _storage.delete(key: _key);

  static Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return true;

    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final hash = await compute(_pbkdf2Isolate, [pin, parts[2], int.tryParse(parts[1]) ?? iterations]);
      return _equals(hash, parts[3]);
    }

    // Formato anterior (SHA-256 con sal): si coincide, se pasa a PBKDF2.
    final parts = stored.split(':');
    final ok = parts.length == 2 && _equals(sha256.convert(utf8.encode('${parts[0]}$pin')).toString(), parts[1]);
    if (ok) await set(pin);
    return ok;
  }

  static bool isValidFormat(String pin) => RegExp('^\\d{$minLength,$maxLength}\$').hasMatch(pin);

  static String _pbkdf2Isolate(List<Object> args) => pbkdf2(args[0] as String, args[1] as String, args[2] as int);

  /// PBKDF2-HMAC-SHA256 (RFC 8018) con una clave de 32 bytes, en base64.
  @visibleForTesting
  static String pbkdf2(String password, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List.fromList([...utf8.encode(salt), 0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  /// Comparación en tiempo constante.
  static bool _equals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
