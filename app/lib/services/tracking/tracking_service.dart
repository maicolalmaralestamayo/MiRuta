import 'dart:convert';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import '../../models/models.dart';
import '../app_settings.dart';
import '../notifications.dart';
import '../sync.dart';
import 'trip_window.dart';
import 'worker_tracker.dart';

/// Servicio de ubicación en primer plano de la ventana de viaje (docs/11
/// §11.41, §11.43 y §11.62): desde X («Inicio ventana») antes de la salida
/// hasta Y («Fin ventana») después de que el viaje termine para el trabajador.
/// Lo arranca la app o, con la app cerrada, la alarma exacta. Cada Z
/// («Frecuencia ventana») toma la posición, calcula el estado del trabajador
/// (y del vehículo si es sensor) y hace UNA sola petición,
/// `POST trips/{id}/reports?cursor=N`, que envía los cambios pendientes (con
/// acuse y reintento) y recibe la línea del recorrido y las novedades de
/// GET sync. Mientras está activo hay una notificación fija.
class TrackingService {
  static const _key = 'tracking';

  static AndroidNotificationOptions get _notificationOptions => AndroidNotificationOptions(
        channelId: 'recorrido',
        channelName: 'Viaje en curso',
        channelDescription: 'Se muestra mientras MiRuta usa la ubicación en la ventana de viaje',
        onlyAlertOnce: true,
      );

  static ForegroundTaskOptions _taskOptions(Duration every) => ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(every.inMilliseconds < 5000 ? 5000 : every.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: true,
      );

  static void init(Duration every) {
    FlutterForegroundTask.init(
      androidNotificationOptions: _notificationOptions,
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: _taskOptions(every),
    );
  }

  /// Opciones del servicio para la alarma exacta (las mismas que envía
  /// FlutterForegroundTask.startService): la app nativa lo arranca con ellas.
  static String alarmPayload(String title, Duration every) => jsonEncode({
        'serviceTypes': [ForegroundServiceTypes.location.rawValue],
        ..._taskOptions(every).toJson(),
        'notificationContentTitle': 'MiRuta: $title',
        'notificationContentText': 'Ventana de viaje abierta',
        ..._notificationOptions.toJson(),
        'callbackHandle': PluginUtilities.getCallbackHandle(trackingCallback)?.toRawHandle(),
      });

  static Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  /// Viaje que se está siguiendo (o null).
  static Future<String?> runningTripId() async {
    if (!await isRunning) return null;
    final raw = await FlutterForegroundTask.getData<String>(key: _key);
    if (raw == null) return null;
    return (jsonDecode(raw) as Map)['tripId']?.toString();
  }

  /// La ubicación está activada y con permiso.
  static Future<bool> locationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  /// Pide el permiso y, si la ubicación está apagada, abre sus ajustes.
  static Future<bool> requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return false;
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  /// Arranca el servicio para la ventana [slot] (con la app a la vista).
  static Future<void> startWindow(WindowSlot slot, AppSettings settings) async {
    if (await isRunning) {
      if (await runningTripId() == slot.trip.id) return;
      await stop();
    }
    await FlutterForegroundTask.removeData(key: _key);
    init(settings.windowEvery);
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'MiRuta: ${slot.trip.title}',
      notificationText: 'Ventana de viaje abierta',
      callback: trackingCallback,
    );
  }

  /// Los hijos que suben con él (se envían al pasar a Viajando o Recogido).
  static Future<void> setChildren(List<String> childIds) async {
    final raw = await FlutterForegroundTask.getData<String>(key: _key);
    if (raw == null) return;
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map)..['childIds'] = childIds;
    await FlutterForegroundTask.saveData(key: _key, value: jsonEncode(data));
  }

  /// Envío inmediato (botón Actualizar con el servicio activo).
  static void syncNow() {
    try {
      FlutterForegroundTask.sendDataToTask('ahora');
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      if (await isRunning) await FlutterForegroundTask.stopService();
      await FlutterForegroundTask.removeData(key: _key);
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void trackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingHandler());
}

/// Cada Z, en el aislamiento del servicio.
class TrackingHandler extends TaskHandler {
  ApiClient? _api;
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Notifications.init();
    _api = await ApiClient.create();
    onRepeatEvent(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_busy) return;
    _busy = true;
    _tick().catchError((_) {}).whenComplete(() => _busy = false);
  }

  @override
  void onReceiveData(Object data) {
    // «Actualizar» en la app: conectar ahora.
    if (data == 'ahora') onRepeatEvent(DateTime.now());
  }

  Future<void> _tick() async {
    final api = _api;
    if (api == null) return;
    await Storage.reload();
    final settings = await AppSettings.cached();
    final now = DateTime.now();
    final slot = await TripWindow.open(settings: settings);
    final raw = await FlutterForegroundTask.getData<String>(key: TrackingService._key);
    var data = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);

    // Sin ventana abierta (o se cerró): se termina el servicio.
    if (slot == null && data['tripId'] == null) {
      await _stop(settings);
      return;
    }
    if (slot != null && data['tripId'] != slot.trip.id) {
      data = {
        'tripId': slot.trip.id,
        'title': slot.trip.title,
        'end': slot.end.toIso8601String(),
        'tracker': null,
        'queue': <Map<String, dynamic>>[],
        'childIds': const <String>[],
        'trip': {'status': slot.trip.status, 'passed': false, 'next': 0},
        'sensors': 0,
      };
    } else if (slot != null) {
      data['end'] = slot.end.toIso8601String();
    }
    final tripId = '${data['tripId']}';
    final title = '${data['title']}';
    final queue = [for (final q in (data['queue'] as List? ?? const [])) Map<String, dynamic>.from(q as Map)];
    final tripInfo = Map<String, dynamic>.from(data['trip'] as Map? ?? const {});
    final ended = data['endedAt'] == null ? null : DateTime.tryParse('${data['endedAt']}');

    // Fin de la ventana: Y después de que el viaje terminó para él.
    final end = DateTime.tryParse('${data['end']}');
    if ((ended != null && now.isAfter(ended.add(settings.windowAfter))) || (end != null && now.isAfter(end))) {
      await _stop(settings);
      return;
    }

    var tracker = data['tracker'] == null ? null : WorkerTracker.fromJson(Map<String, dynamic>.from(data['tracker'] as Map));
    if (tracker == null && ended == null) {
      tracker = await _bootstrap(api, tripId, settings);
    }

    // GPS solo dentro de la ventana y mientras calcula.
    TrackerStep? step;
    bool? gps;
    if (tracker != null && !tracker.finished && ended == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
        );
        gps = true;
        step = tracker.step(
          GeoPoint(position.latitude, position.longitude),
          now,
          TripInfo(status: '${tripInfo['status']}', vehiclePassedMyStop: tripInfo['passed'] == true, nextStopIndex: (tripInfo['next'] as num?)?.toInt() ?? 0),
        );
      } catch (_) {
        // Sin señal del GPS (o sin permiso) en este cálculo: se envía lo pendiente.
        gps = false;
      }
    }

    if (step?.newState != null) {
      final state = step!.newState!;
      final childIds = List<String>.from(data['childIds'] as List? ?? const []);
      queue.add({
        'workerState': state,
        if (step.stopId != null) 'stopId': int.tryParse(step.stopId!),
        if ((state == 'viajando' || state == 'recogido' || state == 'en_parada') && childIds.isNotEmpty) 'childIds': [for (final id in childIds) int.tryParse(id) ?? 0],
        'reportedAt': now.toIso8601String(),
      });
      await Notifications.showMyState(tripId, 'Mi estado: ${WorkerState.name(state)}', title);
      if (state == 'botado' || state == 'dormido') {
        await Notifications.showMyState(tripId, state == 'dormido' ? 'Llegó tarde a la parada' : 'El vehículo pasó sin recogerle', title);
      }
    }

    // Una sola petición: el primer cambio pendiente, el sensor y, de paso, las novedades.
    final pending = queue.isEmpty ? null : queue.first;
    final attributes = <String, dynamic>{
      ...?pending,
      'reportedAt': pending?['reportedAt'] ?? now.toIso8601String(),
      'gps': ?gps,
      if (step != null && step.isSensor) ...{'vehicleState': step.vehicleState, 'nextStopIndex': step.nextStopIndex, 'atStop': step.atStop},
    };
    final foreground = await Storage.isForeground(within: settings.windowEvery * 3);
    final cursor = await SyncService.cursor();
    try {
      final document = await api.post('/trips/$tripId/reports${cursor == null ? '' : '?cursor=$cursor'}', resourceData('trip-reports', attributes: attributes));
      if (pending != null) queue.removeAt(0);
      final live = TripLive.from(document.resource);
      tripInfo['status'] = live.status;
      // Ida: la referencia es la primera parada (salió el vehículo); regreso: la suya.
      final reference = live.outbound ? live.stops.firstOrNull : live.myStop;
      tripInfo['passed'] = reference != null && reference.passed;
      tripInfo['next'] = live.nextStopIndex;
      data['sensors'] = live.sensors;
      // Lo declarado a mano desde la app (o por otra vía) manda sobre el cálculo.
      if (tracker != null && queue.isEmpty && live.myState != null && live.myState != tracker.state && live.myState != 'de_camino') {
        tracker.declare(live.myState!);
      }
      final sync = document.meta['sync'];
      if (sync is Map) {
        final notifications = [for (final n in (sync['data'] as List? ?? const [])) Resource.fromJson(Map<String, dynamic>.from(n as Map))];
        final syncMeta = Map<String, dynamic>.from(sync['meta'] as Map? ?? const {});
        // Con la app abierta, ella muestra los avisos dentro y recarga lo que cambió.
        final result = await SyncService.apply(api, notifications, syncMeta, notify: !foreground, foreground: foreground);
        FlutterForegroundTask.sendDataToMain({
          'changed': result.changed.toList(),
          if (foreground) 'notifications': [for (final n in notifications) n.attributes],
        });
      }
    } on ApiException catch (error) {
      if (!error.isNetwork && pending != null && (error.statusCode == 422 || error.statusCode == 403 || error.statusCode == 404)) queue.removeAt(0);
      if (error.statusCode == 404 || error.statusCode == 403) {
        await TripWindow.markDone(tripId, now.subtract(settings.windowAfter));
        await _stop(settings, reason: '$title. El viaje ya no está disponible. Ya no hace falta la ubicación: puede quitar el GPS.');
        return;
      }
    } catch (_) {
      // Se reintenta en la siguiente vuelta.
    }

    // El viaje terminó para él: estado definitivo o fin del viaje. Sigue Y más.
    final status = '${tripInfo['status']}';
    var endedAt = ended;
    if (endedAt == null && queue.isEmpty && ((tracker?.finished ?? false) || status == 'terminado' || status == 'cancelado')) {
      endedAt = now;
      data['endedAt'] = now.toIso8601String();
      await TripWindow.markDone(tripId, now);
      await Notifications.showDisableGps('$title. ${status == 'terminado' ? 'Terminó el viaje.' : 'Su estado: ${WorkerState.name(tracker?.state)}.'} Ya no hace falta la ubicación: puede quitar el GPS.');
    }

    data['tracker'] = tracker?.toJson();
    data['queue'] = queue.length > 50 ? queue.sublist(queue.length - 50) : queue;
    data['trip'] = tripInfo;
    data['lastAt'] = now.toIso8601String();
    await FlutterForegroundTask.saveData(key: TrackingService._key, value: jsonEncode(data));
    FlutterForegroundTask.sendDataToMain({'nextAt': now.add(settings.windowEvery).toIso8601String()});

    final stateName = endedAt != null ? 'Terminado para usted' : WorkerState.name(tracker?.state);
    final gpsText = gps == false ? ' • sin GPS' : '';
    FlutterForegroundTask.updateService(notificationTitle: 'MiRuta: $stateName • ${data['sensors']} sensores', notificationText: '$title$gpsText');
  }

  /// Primer cálculo: el recorrido (con las coordenadas de las paradas) y su
  /// parada salen de la línea del recorrido.
  Future<WorkerTracker?> _bootstrap(ApiClient api, String tripId, AppSettings settings) async {
    try {
      final live = TripLive.from((await api.get('/trips/$tripId/live')).resource);
      final route = [
        for (final s in live.stops)
          if (s.latitude != null && s.longitude != null) RouteStop(s.stopId, s.landmark, GeoPoint(s.latitude!, s.longitude!)),
      ];
      if (route.length < 2) return null;
      final mine = live.viewerStopId ?? live.myStopId;
      var myIndex = route.indexWhere((s) => s.id == mine);
      if (myIndex < 0) myIndex = live.outbound ? route.length - 1 : 0;
      final config = TrackerConfig(
        stopRadius: settings.distance('radio_parada'),
        gpsTolerance: settings.distance('tolerancia_gps'),
        humanSpeed: settings.speed('velocidad_humana'),
        abandonDistance: settings.distance('distancia_abandono'),
        consecutive: settings.integer('calculos_consecutivos'),
        finalWait: settings.duration('espera_final'),
      );
      final tracker = WorkerTracker(outbound: live.outbound, route: route, myIndex: myIndex, config: config);
      if (live.myState != null) tracker.declare(live.myState!);
      return tracker;
    } catch (_) {
      return null;
    }
  }

  Future<void> _stop(AppSettings settings, {String? reason}) async {
    if (reason != null) await Notifications.showDisableGps(reason);
    await FlutterForegroundTask.removeData(key: TrackingService._key);
    // La próxima ventana (si la hay) queda programada antes de cerrar.
    await TripWindow.reschedule(settings);
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
