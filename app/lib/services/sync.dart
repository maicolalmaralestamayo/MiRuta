import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
import '../core/local_cache.dart';
import '../core/storage.dart';
import 'app_settings.dart';
import 'app_updates.dart';
import 'notifications.dart';
import 'prefetch.dart';
import 'qr/qr_queue.dart';
import 'tracking/trip_window.dart';

/// El próximo viaje (o el que está en ejecución) según GET sync.
class NextTrip {
  final String id;
  final String direction;
  final String status;
  final DateTime departsAt;
  final bool today;
  final String? itineraryId;

  const NextTrip({required this.id, required this.direction, required this.status, required this.departsAt, this.today = false, this.itineraryId});

  factory NextTrip.fromJson(Map<String, dynamic> j) => NextTrip(
        id: '${j['id']}',
        direction: '${j['direction'] ?? 'ida'}',
        status: '${j['status'] ?? 'planificado'}',
        departsAt: DateTime.tryParse('${j['departsAt']}')?.toLocal() ?? DateTime.now(),
        today: j['today'] == true,
        itineraryId: j['itineraryId']?.toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'direction': direction, 'status': status, 'departsAt': departsAt.toIso8601String(), 'today': today, 'itineraryId': itineraryId};

  bool get isToday {
    final now = DateTime.now();
    return today || (departsAt.year == now.year && departsAt.month == now.month && departsAt.day == now.day);
  }
}

/// Resultado de una sincronización.
class SyncResult {
  final Set<String> changed;
  final Map<String, int> counters;
  final NextTrip? nextTrip;
  final bool settingsChanged;

  /// El registro de cambios cambió lo guardado en el teléfono (las pantallas
  /// abiertas vuelven a leerlo, sin spinner; docs/11 §11.65).
  final bool cacheChanged;

  const SyncResult({this.changed = const {}, this.counters = const {}, this.nextTrip, this.settingsChanged = false, this.cacheChanged = false});
}

/// Sincronización con `GET sync?cursor=N` (docs/13 §13.10): notificaciones
/// del teléfono, contadores, próximo viaje, ajustes y versión de la app. La
/// usan la app abierta (con su frecuencia y el botón Actualizar) y la tarea
/// en segundo plano.
class SyncService {
  static const _cursorKey = 'user.sync.cursor';
  static const _countersKey = 'user.sync.counters';
  static const _nextTripKey = 'user.sync.next_trip';
  static const _frequencyKey = 'user.sync.frequency';

  /// Cursor del registro de cambios (docs/11 §11.65); sin él, descargarlo todo.
  static const _changesKey = 'user.sync.changes';
  static const meKey = 'user.me';
  static const task = 'miruta-sync';

  static Future<Map<String, int>> cachedCounters() async =>
      (await Storage.getJson(_countersKey)).map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

  static Future<NextTrip?> cachedNextTrip() async {
    final json = await Storage.getJson(_nextTripKey);
    return json['id'] == null ? null : NextTrip.fromJson(json);
  }

  /// [foreground]: la app está a la vista (para abrir la ventana de viaje).
  /// Las notificaciones salen siempre en la cortina (docs/11 §11.63).
  static Future<SyncResult> run(ApiClient api, {bool notify = true, bool foreground = false}) async {
    var cursor = await Storage.getString(_cursorKey);
    final notifications = <Resource>[];
    Map<String, dynamic> meta = const {};
    var cacheChanged = false;
    for (var round = 0; round < 10; round++) {
      final document = await api.get('/sync', query: {'cursor': ?cursor, 'changes': await changesCursor()});
      if (cursor != null) notifications.addAll(document.resources);
      meta = document.meta;
      cursor = meta['cursor']?.toString() ?? cursor;
      final more = meta['more'] == true || (meta['changes'] is Map && (meta['changes'] as Map)['more'] == true);
      // Las vueltas intermedias solo aplican el registro de cambios.
      if (more) cacheChanged = await applyChanges(api, meta['changes']) || cacheChanged;
      if (!more) break;
    }
    final result = await apply(api, notifications, meta, notify: notify, foreground: foreground);
    return cacheChanged && !result.cacheChanged
        ? SyncResult(changed: result.changed, counters: result.counters, nextTrip: result.nextTrip, settingsChanged: result.settingsChanged, cacheChanged: true)
        : result;
  }

  /// Cursor que se envía en la siguiente consulta (también dentro de la
  /// ventana de viaje, en POST trips/{id}/reports?cursor=N).
  static Future<String?> cursor() => Storage.getString(_cursorKey);

  /// Cursor del registro de cambios ('' = empezar: descargarlo todo).
  static Future<String> changesCursor() async => await Storage.getString(_changesKey) ?? '';

  /// Aplica meta.changes (docs/11 §11.65): lo cambiado en lo guardado; con
  /// full, vuelve a descargarlo todo por detrás. Devuelve true si cambió algo.
  static Future<bool> applyChanges(ApiClient api, Object? raw) async {
    if (raw is! Map) return false;
    final changes = Map<String, dynamic>.from(raw);
    final next = changes['cursor']?.toString();
    var changed = false;
    if (changes['full'] == true) {
      // Más viejo que lo que conserva el servidor (o la primera vez): todo de nuevo.
      await LocalCache.markStale([await for (final (key, _) in LocalCache.entries()) key]);
      if (next != null) await Storage.setString(_changesKey, next);
      await Prefetch.run(api);
      await LocalCache.feedApplied();
      return true;
    }
    final (any, lists) = await LocalCache.applyChanges(CacheChanges.fromJson(changes));
    changed = any;
    if (next != null) await Storage.setString(_changesKey, next);
    // Las listas de tipos con altas, por detrás (las demás marcadas se preguntan al abrirlas).
    if (lists.isNotEmpty) changed = await Prefetch.refreshStale(api, lists.toSet()) || changed;
    return changed;
  }

  /// Aplica lo recibido (de GET sync o del meta.sync de un informe del
  /// viaje): notificaciones, contadores, versión de la app, ajustes, viajes
  /// propios (ventana de viaje), huellas de los datos (caché) e inclusiones
  /// por QR pendientes.
  static Future<SyncResult> apply(ApiClient api, List<Resource> notifications, Map<String, dynamic> meta, {bool notify = true, bool foreground = false}) async {
    final changed = <String>{};
    final hadCursor = await Storage.getString(_cursorKey) != null;
    for (final n in notifications) {
      if (notify && hadCursor) {
        await Notifications.showServer(n.string('kind') ?? '', n.string('title') ?? 'MiRuta', n.string('body') ?? '',
            Map<String, dynamic>.from(n.attributes['data'] as Map? ?? const {}));
      }
    }
    changed.addAll([for (final c in (meta['changed'] as List? ?? const [])) '$c']);
    // Registro de cambios (4.4.0): lo guardado se pone al día sin avisar.
    final cacheChanged = await applyChanges(api, meta['changes']);
    if (meta['cursor'] != null) await Storage.setString(_cursorKey, meta['cursor'].toString());

    final counters = <String, int>{
      for (final e in (meta['counters'] as Map? ?? const {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0,
    };
    await Storage.setJson(_countersKey, counters);

    // Solicitudes pendientes, respuestas vistas, mensajes leídos y viajes terminados (docs/11 §11.63).
    if (notify) await Notifications.applyMeta(meta, counters);

    // Actualización disponible u obligatoria: una sola notificación, con el
    // tamaño de la APK de este teléfono; se quita al instalar la versión.
    final latest = meta['latestAppVersion'];
    if (latest is Map && latest['updateAvailable'] == true) {
      final code = (latest['versionCode'] as num?)?.toInt() ?? 0;
      final mandatory = latest['mandatory'] == true;
      if (notify && !await Notifications.updateShown(code, mandatory)) {
        String? size;
        try {
          final update = await AppUpdates.check(api);
          if (update != null && update.sizeBytes > 0) size = update.sizeLabel;
        } catch (_) {}
        await Notifications.showUpdate('${latest['versionName']}', versionCode: code, mandatory: mandatory, size: size);
      }
    } else if (latest is Map || meta.containsKey('latestAppVersion')) {
      await Notifications.cancelUpdate();
    }

    // Ajustes: si cambió su versión, se recargan.
    var settings = await AppSettings.cached();
    var settingsChanged = false;
    if (meta['settingsVersion'] != null && meta['settingsVersion'].toString() != settings.version) {
      try {
        settings = (await AppSettings.refresh(api)).$1;
        settingsChanged = true;
      } catch (_) {}
    }

    // Huellas de la 4.3.0: solo con un servidor viejo (sin registro de cambios).
    if (meta['changes'] == null) changed.addAll(await LocalCache.compareVersions(meta['versions']));

    // Viajes en que viaja: su ventana de viaje.
    if (meta['myTrips'] is List) {
      await TripWindow.save([for (final t in meta['myTrips'] as List) Map<String, dynamic>.from(t as Map)]);
    }

    // Próximo viaje (el aviso de la ubicación va en «Mi estado», docs/11 §11.63).
    NextTrip? next;
    final rawNext = meta['nextTrip'];
    if (rawNext is Map) {
      next = NextTrip.fromJson(Map<String, dynamic>.from(rawNext));
      await Storage.setJson(_nextTripKey, next.toJson());
    } else if (meta.containsKey('nextTrip')) {
      await Storage.setString(_nextTripKey, null);
    }

    // Inclusiones por QR hechas sin conexión.
    try {
      await QrQueue.flush(api);
    } catch (_) {}

    await TripWindow.reschedule(settings, foreground: foreground);
    await scheduleBackground(settings);
    return SyncResult(changed: changed, counters: counters, nextTrip: next, settingsChanged: settingsChanged, cacheChanged: cacheChanged);
  }

  /// Con la app cerrada y fuera de la ventana de viaje, solo recibe cada
  /// «Frecuencia larga» (docs/11 §11.65): la tarea en segundo plano (Android
  /// no permite menos de 15 minutos), sin GPS.
  static Future<void> scheduleBackground(AppSettings settings) async {
    final minutes = settings.longEvery.inMinutes;
    if (await Storage.getString(_frequencyKey) == '$minutes') return;
    try {
      await Workmanager().registerPeriodicTask(
        task,
        task,
        frequency: Duration(minutes: minutes),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      await Storage.setString(_frequencyKey, '$minutes');
    } catch (_) {
      // Fuera de Android (pruebas).
    }
  }
}
