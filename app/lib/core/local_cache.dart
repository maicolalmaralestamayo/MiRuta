import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Lo guardado de una consulta: el cuerpo JSON, su huella (ETag) y cuándo se
/// guardó o se comprobó por última vez.
class CacheEntry {
  final Map<String, dynamic> body;
  final String? etag;
  final DateTime savedAt;

  const CacheEntry(this.body, this.etag, this.savedAt);
}

/// No hay nada guardado de esa consulta (lectura solo de la caché).
class CacheMiss implements Exception {
  const CacheMiss();
}

/// Rastro de las consultas de una carga (lo usa DataView): si todo salió de
/// la caché, de cuándo es lo más viejo y si fue por falta de conexión.
class CacheTrace {
  static final _key = Object();

  static CacheTrace? get current => Zone.current[_key] as CacheTrace?;

  /// Solo la caché, sin conexión (primera vista inmediata de la pantalla).
  final bool cacheOnly;
  DateTime? oldest;

  /// Alguna consulta no llegó al servidor y se usó lo guardado.
  bool offline = false;

  CacheTrace({this.cacheOnly = false});

  void used(DateTime savedAt, {bool stale = false}) {
    if (oldest == null || savedAt.isBefore(oldest!)) oldest = savedAt;
    if (stale) offline = true;
  }

  Future<T> run<T>(Future<T> Function() action) => runZoned(action, zoneValues: {_key: this});
}

/// Caché local de la app (docs/11 §11.62): perfil, Entidades, itinerarios,
/// paradas, trabajadores, hijos, solicitudes, nomencladores, ajustes, viajes
/// de los próximos días y la conversación, en archivos del teléfono (sin
/// paquetes nuevos). Al abrir una pantalla se muestra al momento lo guardado
/// («Actualizado hace …») y por detrás se pregunta al servidor solo si cambió
/// (If-None-Match: si no cambió responde 304 sin datos). La línea del
/// recorrido en tiempo real no se guarda. Al cerrar sesión se borra.
class LocalCache {
  static const _versionsKey = 'user.cache.versions';

  /// Lo que no se guarda: tiempo real, sincronización, mantenimiento y lo público.
  static final _excluded = RegExp(r'^/(sync|server-status|maintenance-runs|registration-status|password-policy|password-suggestion|username-suggestion|'
      r'qr-public-key|app-versions/latest|entities/lookup|guest/.*|trips/\d+/(live|passengers|reports))$');

  /// Se puede apagar (pruebas de widgets: sin archivos del teléfono).
  static bool enabled = true;

  static bool cacheable(String path) => enabled && !_excluded.hasMatch(path.split('?').first);

  static Directory? _dir;

  static Future<Directory> _directory() async {
    final dir = _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Clave de una consulta: ruta y parámetros ordenados.
  static String keyFor(String path, Map<String, dynamic>? query) {
    final params = (query ?? const {}).entries.where((e) => e.value != null).map((e) => '${e.key}=${e.value}').toList()..sort();
    return params.isEmpty ? path : '$path?${params.join('&')}';
  }

  /// Nombre de archivo (FNV-1a de 64 bits en hexadecimal).
  static String fileName(String key) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final unit in utf8.encode(key)) {
      hash ^= unit;
      hash = hash * prime;
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(hash >>> 32)}${hex(hash & 0xFFFFFFFF)}.json';
  }

  static Future<File> _file(String key) async => File('${(await _directory()).path}/${fileName(key)}');

  static Future<CacheEntry?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map;
      if (json['key'] != key) return null;
      return CacheEntry(Map<String, dynamic>.from(json['body'] as Map), json['etag'] as String?, DateTime.tryParse('${json['savedAt']}') ?? DateTime(2000));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> body, String? etag, {DateTime? at}) async {
    try {
      final file = await _file(key);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({'key': key, 'etag': etag, 'savedAt': (at ?? DateTime.now()).toIso8601String(), 'body': body}), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Sin espacio o sin carpeta: se sigue sin caché.
    }
  }

  /// Borra todo lo guardado (al cerrar sesión).
  static Future<void> clear() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }

  /// Compara las huellas de meta.versions de GET sync con las guardadas:
  /// devuelve los grupos que cambiaron y, si alguno cambió, «data» (las
  /// pantallas abiertas vuelven a preguntar, solo por lo que cambió).
  static Future<Set<String>> compareVersions(Object? versions) async {
    if (versions is! Map) return const {};
    final stored = await Storage.getJson(_versionsKey);
    final changed = <String>{
      for (final e in versions.entries)
        if (stored['${e.key}'] != null && stored['${e.key}'] != e.value) '${e.key}',
    };
    await Storage.setJson(_versionsKey, {for (final e in versions.entries) '${e.key}': e.value});
    return changed.isEmpty ? const {} : {...changed, 'data'};
  }
}

/// «hace 5 min», «hace 2 h», «hace 3 días» (o «ahora»).
String agoText(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 60) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  final days = d.inDays;
  return 'hace $days ${days == 1 ? 'día' : 'días'}';
}
