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

  /// Algo de lo guardado puede no estar al día (el registro de cambios avisó
  /// de altas en su tipo, o no lo cubre): conviene preguntar al servidor.
  bool stale = false;

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
  static const _staleKey = 'user.cache.stale';
  static const _changesAtKey = 'user.cache.changes_at';

  /// Lo que mantiene al día el registro de cambios (docs/11 §11.65): las
  /// consultas de estos tipos (listas y registros). Lo demás (resúmenes, «me»)
  /// se vuelve a preguntar al abrir la pantalla.
  static const feedTypes = {
    'entities', 'itineraries', 'itinerary-stops', 'stops', 'users', 'workers', 'worker-itineraries', 'applications', 'children',
    'absences', 'vehicle-types', 'absence-types', 'conversation-topics', 'entity-denial-reasons', 'itinerary-denial-reasons',
    'detention-causes', 'trips', 'conversations',
  };

  /// Tipo de la consulta según su ruta («/stops/3?…» → stops), o null.
  static String? typeOf(String key) {
    final path = key.split('?').first;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.length > 2 || !feedTypes.contains(parts.first)) return null;
    if (parts.length == 2 && int.tryParse(parts[1]) == null) return null;
    return parts.first;
  }

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

  /// Todas las claves guardadas (con su cuerpo), para aplicar el registro de cambios.
  static Stream<(String, CacheEntry)> entries() async* {
    final dir = await _directory();
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await f.readAsString()) as Map;
        yield ('${json['key']}', CacheEntry(Map<String, dynamic>.from(json['body'] as Map), json['etag'] as String?, DateTime.tryParse('${json['savedAt']}') ?? DateTime(2000)));
      } catch (_) {}
    }
  }

  static Future<void> remove(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Consultas que hay que volver a pedir por detrás (listas con altas).
  static Future<Set<String>> staleKeys() async => {for (final k in (await Storage.getJson(_staleKey)).keys) k};

  static Future<bool> isStale(String key) async => (await Storage.getJson(_staleKey)).containsKey(key);

  static Future<void> markStale(Iterable<String> keys) async {
    if (keys.isEmpty) return;
    final json = await Storage.getJson(_staleKey);
    for (final k in keys) {
      json[k] = true;
    }
    await Storage.setJson(_staleKey, json);
  }

  static Future<void> markFresh(String key) async {
    final json = await Storage.getJson(_staleKey);
    if (json.remove(key) != null) await Storage.setJson(_staleKey, json);
  }

  /// El registro de cambios se aplicó hace poco: lo guardado está al día.
  static Future<bool> feedActive({Duration within = const Duration(minutes: 30)}) async {
    final at = DateTime.tryParse(await Storage.getString(_changesAtKey) ?? '');
    return at != null && DateTime.now().difference(at) < within;
  }

  static Future<void> feedApplied() => Storage.setString(_changesAtKey, DateTime.now().toIso8601String());

  /// Aplica el registro de cambios a todo lo guardado. Devuelve si algo
  /// cambió (las pantallas abiertas vuelven a leer lo guardado) y las listas
  /// con altas, que hay que volver a pedir.
  static Future<(bool, List<String>)> applyChanges(CacheChanges changes) async {
    if (!enabled) return (false, const <String>[]);
    if (changes.isEmpty) {
      await feedApplied();
      return (false, const <String>[]);
    }
    var any = false;
    final stale = <String>[];
    final pending = <(String, CacheEntry)>[];
    await for (final e in entries()) {
      pending.add(e);
    }
    for (final (key, entry) in pending) {
      final (body, isStale) = changes.applyTo(key, entry.body);
      if (isStale) stale.add(key);
      if (body == null) {
        await remove(key);
        any = true;
      } else if (!identical(body, entry.body)) {
        // Lo cambiado ya no coincide con la huella del servidor: sin ETag.
        await write(key, body, null, at: entry.savedAt);
        any = true;
      }
    }
    await markStale(stale);
    await feedApplied();
    return (any || stale.isNotEmpty, stale);
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

/// Registro de cambios en el teléfono (docs/11 §11.65): aplica a lo guardado
/// los registros cambiados (y los borrados) que devuelve GET sync?changes=N,
/// sin avisar ni mostrar spinner, y marca para volver a pedir por detrás las
/// listas de los tipos con altas (el teléfono no sabe si entran en sus filtros).
class CacheChanges {
  /// Recursos JSON:API cambiados, como los devuelve GET tipo/id.
  final List<Map<String, dynamic>> data;

  /// Tipo => ids borrados (o que ya no ve).
  final Map<String, Set<String>> deleted;

  /// Tipos con cambios.
  final Set<String> changed;

  const CacheChanges({this.data = const [], this.deleted = const {}, this.changed = const {}});

  factory CacheChanges.fromJson(Map<String, dynamic> j) => CacheChanges(
        data: [for (final r in (j['data'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)],
        deleted: {
          if (j['deleted'] is Map)
            for (final e in (j['deleted'] as Map).entries) '${e.key}': {for (final id in (e.value as List? ?? const [])) '$id'},
        },
        changed: {for (final t in (j['changed'] as List? ?? const [])) '$t'},
      );

  bool get isEmpty => data.isEmpty && deleted.values.every((v) => v.isEmpty) && changed.isEmpty;

  String _ref(Map r) => '${r['type']}:${r['id']}';

  /// Aplica los cambios a un cuerpo guardado. Devuelve el cuerpo nuevo, el
  /// mismo si no cambió, o null si hay que borrarlo (el registro ya no existe).
  /// [stale] queda en true si es una lista de un tipo con cambios.
  (Map<String, dynamic>?, bool stale) applyTo(String key, Map<String, dynamic> body) {
    final byRef = {for (final r in data) _ref(r): r};
    bool gone(Map r) => deleted['${r['type']}']?.contains('${r['id']}') ?? false;
    var touched = false;
    var stale = false;

    Object? patch(Object? item) {
      if (item is! Map) return item;
      final replacement = byRef[_ref(item)];
      if (replacement != null) {
        touched = true;
        return replacement;
      }
      return item;
    }

    final primary = body['data'];
    Object? newPrimary = primary;
    if (primary is List) {
      final kept = <Object?>[];
      for (final item in primary) {
        if (item is Map && gone(item)) {
          touched = true;
          continue;
        }
        kept.add(patch(item));
      }
      newPrimary = kept;
      final type = LocalCache.typeOf(key);
      if (type != null && changed.contains(type)) stale = true;
    } else if (primary is Map) {
      if (gone(primary)) return (null, false);
      newPrimary = patch(primary);
    }
    final included = body['included'];
    Object? newIncluded = included;
    if (included is List) {
      newIncluded = [for (final item in included) if (!(item is Map && gone(item))) patch(item)];
      if ((newIncluded as List).length != included.length) touched = true;
    }
    if (!touched) return (body, stale);
    return ({...body, 'data': newPrimary, if (included != null) 'included': newIncluded}, stale);
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
