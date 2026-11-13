import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/formats.dart';
import '../core/storage.dart';
import 'app_settings.dart';
import 'app_updates.dart';
import 'notifications.dart';
import 'qr/qr_queue.dart';

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

  const SyncResult({this.changed = const {}, this.counters = const {}, this.nextTrip, this.settingsChanged = false});
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
  static const meKey = 'user.me';
  static const task = 'miruta-sync';

  static Future<Map<String, int>> cachedCounters() async =>
      (await Storage.getJson(_countersKey)).map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

  static Future<NextTrip?> cachedNextTrip() async {
    final json = await Storage.getJson(_nextTripKey);
    return json['id'] == null ? null : NextTrip.fromJson(json);
  }

  /// [foreground]: la app está abierta; las notificaciones se muestran dentro
  /// de ella y no en el teléfono (docs/11 §11.56).
  static Future<SyncResult> run(ApiClient api, {bool notify = true, bool foreground = false}) async {
    final me = await Storage.getJson(meKey);
    var cursor = await Storage.getString(_cursorKey);
    final changed = <String>{};
    Map<String, dynamic> meta = const {};
    for (var round = 0; round < 10; round++) {
      final document = await api.get('/sync', query: {'cursor': ?cursor});
      for (final n in document.resources) {
        if (notify && cursor != null) {
          await Notifications.showServer(n.string('kind') ?? '', n.string('title') ?? 'MiRuta', n.string('body') ?? '',
              Map<String, dynamic>.from(n.attributes['data'] as Map? ?? const {}), foreground: foreground);
        }
      }
      meta = document.meta;
      changed.addAll([for (final c in (meta['changed'] as List? ?? const [])) '$c']);
      cursor = meta['cursor']?.toString() ?? cursor;
      await Storage.setString(_cursorKey, cursor);
      if (meta['more'] != true) break;
    }

    final counters = <String, int>{
      for (final e in (meta['counters'] as Map? ?? const {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0,
    };
    await Storage.setJson(_countersKey, counters);

    // Actualización disponible: una notificación por versión.
    final latest = meta['latestAppVersion'];
    if (latest is Map && latest['updateAvailable'] == true) {
      final code = (latest['versionCode'] as num?)?.toInt() ?? 0;
      if (notify && await AppUpdates.shouldNotify(code)) await Notifications.showUpdate('${latest['versionName']}', mandatory: latest['mandatory'] == true);
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

    // Próximo viaje: recordatorio de activar la ubicación.
    NextTrip? next;
    final rawNext = meta['nextTrip'];
    if (rawNext is Map) {
      final previous = await cachedNextTrip();
      next = NextTrip.fromJson(Map<String, dynamic>.from(rawNext));
      var itineraryId = previous?.id == next.id ? previous?.itineraryId : null;
      if (itineraryId == null) {
        try {
          itineraryId = (await api.get('/trips/${next.id}')).resource.relId('itinerary')?.id;
        } catch (_) {}
      }
      next = NextTrip(id: next.id, direction: next.direction, status: next.status, departsAt: next.departsAt, today: next.today, itineraryId: itineraryId);
      await Storage.setJson(_nextTripKey, next.toJson());
      final mine = (me['travelItineraryIds'] as List? ?? const []).map((e) => '$e').contains(itineraryId);
      if (mine && next.status == 'planificado') {
        await Notifications.scheduleLocationReminder(
          tripId: next.id,
          at: next.departsAt.subtract(settings.duration('anticipacion_viaje')),
          body: 'Su viaje de ${next.direction} sale a las ${formatTime(next.departsAt)}. Active la ubicación (GPS) y abra MiRuta.',
        );
      }
    } else {
      await Storage.setString(_nextTripKey, null);
    }

    // Inclusiones por QR hechas sin conexión.
    try {
      await QrQueue.flush(api);
    } catch (_) {}

    await scheduleBackground(next, settings);
    return SyncResult(changed: changed, counters: counters, nextTrip: next, settingsChanged: settingsChanged);
  }

  /// Frecuencia de consulta según haya viaje ese día (docs/11 §11.44).
  static Duration frequency(NextTrip? next, AppSettings settings) =>
      next != null && (next.isToday || next.status == 'en_ejecucion') ? settings.duration('frecuencia_dia_viaje') : settings.duration('frecuencia_reposo');

  /// Tarea en segundo plano (Android no permite menos de 15 minutos).
  static Future<void> scheduleBackground(NextTrip? next, AppSettings settings) async {
    var minutes = frequency(next, settings).inMinutes;
    if (minutes < 15) minutes = 15;
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
