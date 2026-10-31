import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Instalación de la app en este teléfono (docs/08-version-2.md §8.6 y §8.7).
///
/// La primera vez que hace falta (hablar con el desarrollador o recuperar el
/// acceso sin cuenta) se registra en el servidor y se guarda su secreto. Va en
/// la cabecera X-Installation de esas peticiones y al iniciar sesión.
class Installation {
  static const _key = 'installation_header';
  static const _secure = FlutterSecureStorage();

  /// Valor de la cabecera X-Installation, o null si aún no se registró.
  static Future<String?> header() => _secure.read(key: _key);

  /// Registra la instalación si hace falta y devuelve la cabecera.
  static Future<String> ensure(Dio dio) async {
    final existing = await header();
    if (existing != null) return existing;

    final info = await deviceInfo();
    final response = await dio.post<dynamic>('/installations',
        data: {
          'data': {
            'type': 'installations',
            'attributes': {
              'deviceModel': info['model'],
              'androidVersion': info['androidVersion'],
              'appVersionCode': int.tryParse((await PackageInfo.fromPlatform()).buildNumber),
            },
          },
        },
        options: Options(extra: {'auth': false}));
    final value = (response.data as Map)['data']['meta']['header'] as String;
    await _secure.write(key: _key, value: value);
    return value;
  }

  /// Olvida la instalación (p. ej. si el servidor ya no la reconoce).
  static Future<void> forget() => _secure.delete(key: _key);

  static Future<Map<String, String?>> deviceInfo() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      return {
        'model': '${android.manufacturer} ${android.model}'.trim(),
        'androidVersion': android.version.release,
      };
    } catch (_) {
      return {'model': null, 'androidVersion': null};
    }
  }

  /// Tipos de procesador que admite Android, por preferencia (p. ej.
  /// arm64-v8a, armeabi-v7a). Un teléfono de 64 bits con Android de 32 bits
  /// solo dice armeabi-v7a, y es lo que importa para instalar.
  static Future<List<String>> supportedAbis() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      return const ['arm64-v8a', 'armeabi-v7a'];
    }
  }
}
