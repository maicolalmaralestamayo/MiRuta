import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Nombre, versión y arquitectura de la app instalada (docs/09 §1 y §13).
class AppInfo {
  static const name = 'MiRuta';
  static const _channel = MethodChannel('mitransporte/app');

  static String? _label;

  /// "MiRuta · Versión 2.1.0 · 64 bits".
  static Future<String> label() async {
    if (_label != null) return _label!;
    final version = (await PackageInfo.fromPlatform()).version;
    final bits = await architectureBits();
    return _label = '$name · Versión $version${bits == null ? '' : ' · $bits bits'}';
  }

  /// 64 o 32 según el APK instalado (sus bibliotecas nativas), o null si no se sabe.
  static Future<int?> architectureBits() async {
    try {
      final installed = Map<String, dynamic>.from(await _channel.invokeMethod('installedApk') as Map);
      final dir = installed['nativeLibraryDir'] as String? ?? '';
      if (dir.endsWith('arm64') || dir.endsWith('arm64-v8a') || dir.endsWith('x86_64')) return 64;
      if (dir.endsWith('arm') || dir.endsWith('armeabi-v7a') || dir.endsWith('x86')) return 32;
      return null;
    } catch (_) {
      return null;
    }
  }
}
