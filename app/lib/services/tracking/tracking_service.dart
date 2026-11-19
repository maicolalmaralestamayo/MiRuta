import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/server_clock.dart';
import '../../core/storage.dart';
import '../../models/models.dart';
import '../app_settings.dart';
import '../notification_texts.dart';
import '../notifications.dart';
import '../sync.dart';
import 'trip_window.dart';
import 'worker_tracker.dart';

/// Servicio de ubicación en primer plano de la ventana de viaje (docs/11
/// §11.41, §11.43 y §11.62): desde X («Inicio ventana») antes de la salida
/// hasta Y («Fin ventana») después de que el viaje termine para el trabajador.
/// Lo arranca la app o, con la app cerrada, la alarma exacta. Cada Z
/// («Frecuencia corta») toma la posición, calcula el estado del trabajador
/// (y del vehículo si es sensor) y hace UNA sola petición,
/// `POST trips/{id}/reports?cursor=N`, que envía los cambios pendientes (con
/// acuse y reintento) y recibe la línea del recorrido y las novedades de
/// GET sync. Mientras está activo, su notificación fija es «Mi estado» y,
/// con el viaje en ejecución, mantiene la del vehículo (docs/11 §11.63).
class TrackingService {
  static const _key = 'tracking';

  /// Lo tocado en «Mi estado» (gps, permiso o trip:N), para la app al abrirse.
  static const tapKey = 'user.tracking.tap';

  static AndroidNotificationOptions get _notificationOptions => AndroidNotificationOptions(
        channelId: Notifications.channelMyState,
        channelName: 'Mi estado',
        channelDescription: 'Su estado en el viaje mientras MiRuta usa la ubicación',
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
        'notificationContentTitle': 'Mi estado',
        'notificationContentText': title,
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
  /// Lo calculado en el teléfono para la tarjeta de estado de «Ver recorrido»
  /// (docs/11 §11.67): estado, parada, movimiento, velocidad y última
  /// ubicación con su hora. Lo envía el servicio tras cada cálculo.
  static final myMotion = ValueNotifier<MyMotion?>(null);

  /// Lo último calculado por el servicio para el viaje [tripId] (o null).
  static Future<MyMotion?> lastMotion(String tripId) async {
    try {
      final raw = await FlutterForegroundTask.getData<String>(key: _key);
      if (raw == null) return null;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if ('${data['tripId']}' != tripId || data['me'] is! Map) return null;
      return MyMotion.fromJson(Map<String, dynamic>.from(data['me'] as Map));
    } catch (_) {
      return null;
    }
  }

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
    init(settings.shortEvery);
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'Mi estado',
      notificationText: itineraryLine(slot.trip.itineraryName, slot.trip.direction),
      callback: trackingCallback,
    );
  }

  /// Los hijos que suben con él (se envían al pasar a Viajando).
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

  /// Tocar «Mi estado»: la app se abre y, sin GPS o sin «Permitir todo el
  /// tiempo», lleva a los ajustes (docs/11 §11.63); si no, a la línea del recorrido.
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.getData<String>(key: TrackingService._key).then((raw) async {
      final data = raw == null ? const {} : jsonDecode(raw) as Map;
      final tap = '${data['tap'] ?? (data['tripId'] == null ? '' : 'trip:${data['tripId']}')}';
      if (tap.isEmpty) return;
      await Storage.setString(TrackingService.tapKey, tap);
      FlutterForegroundTask.sendDataToMain({'tap': tap});
    }).catchError((_) {});
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
    await ServerClock.load();
    final settings = await AppSettings.cached();
    final now = DateTime.now();
    final slot = await TripWindow.open(settings: settings);
    final raw = await FlutterForegroundTask.getData<String>(key: TrackingService._key);
    var data = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);

    // Sin ventana abierta (o se cerró, p. ej. al dejar de ver el recorrido de un viaje
    // que aún no empieza): se termina el servicio.
    if (slot == null) {
      await _stop(settings);
      return;
    }
    if (data['tripId'] != slot.trip.id) {
      data = {
        'tripId': slot.trip.id,
        'title': slot.trip.title,
        'itinerary': slot.trip.itineraryName,
        'outbound': slot.trip.outbound,
        'end': slot.end.toIso8601String(),
        'tracker': null,
        'queue': <Map<String, dynamic>>[],
        'childIds': const <String>[],
        'trip': {'status': slot.trip.status, 'states': <String, String>{}, 'left': <int>[], 'next': 0},
        'sensors': 0,
      };
    } else {
      data['end'] = slot.end.toIso8601String();
    }
    final tripId = '${data['tripId']}';
    // Cola de cambios con su hora de captura (docs/11 §11.65); los de la 4.3.0 se convierten.
    final queue = [for (final q in (data['queue'] as List? ?? const [])) _event(Map<String, dynamic>.from(q as Map))];
    final tripInfo = Map<String, dynamic>.from(data['trip'] as Map? ?? const {});
    final ended = data['endedAt'] == null ? null : DateTime.tryParse('${data['endedAt']}');

    // Fin de la ventana: Y después de que el viaje terminó para él.
    final end = DateTime.tryParse('${data['end']}');
    if ((ended != null && now.isAfter(ended.add(settings.windowAfter))) || (end != null && now.isAfter(end))) {
      await _stop(settings);
      return;
    }

    var tracker = data['tracker'] == null || (data['tracker'] as Map)['version'] != 50
        ? null
        : WorkerTracker.fromJson(Map<String, dynamic>.from(data['tracker'] as Map));
    if (tracker == null && ended == null) tracker = await _bootstrap(api, tripId, settings);

    // GPS encendido y permiso «todo el tiempo» (para «Mi estado»).
    final gpsOn = await _safe(Geolocator.isLocationServiceEnabled, true);
    final permission = await _safe(Geolocator.checkPermission, LocationPermission.always);

    // GPS solo dentro de la ventana y mientras calcula.
    TrackerStep? step;
    bool? gps;
    if (!gpsOn && tracker != null && !tracker.finished && ended == null) gps = false;
    if (gpsOn && tracker != null && !tracker.finished && ended == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
        ).timeout(const Duration(seconds: 25));
        gps = true;
        step = tracker.step(GeoPoint(position.latitude, position.longitude), now, tripInfoFrom(tripInfo));
        data['position'] = {'lat': position.latitude, 'lon': position.longitude, 'at': now.toIso8601String()};
      } catch (_) {
        // Sin señal del GPS (o sin permiso) en este cálculo: se envía lo pendiente.
        gps = false;
      }
    }

    final childIds = List<String>.from(data['childIds'] as List? ?? const []);
    if (step?.newState != null) queue.add(workerEvent(step!.newState!, step.stopId, now, childIds: childIds));
    // Observación del sensor sobre el vehículo, con su hora: en cola si cambió.
    if (step != null && step.isSensor) {
      final observation = vehicleEvent(step, now);
      final last = data['lastVehicle'] is Map ? Map<String, dynamic>.from(data['lastVehicle'] as Map) : null;
      if (last == null || !sameObservation(last, observation)) queue.add(observation);
      data['lastVehicle'] = observation;
    }

    // Una sola petición: toda la cola (con la observación actual) y, de paso, las novedades.
    final fromQueue = queue.length < 100 ? queue.length : 100;
    final sending = [...queue.take(fromQueue)];
    final current = data['lastVehicle'] is Map && tracker?.isSensor == true ? Map<String, dynamic>.from(data['lastVehicle'] as Map) : null;
    if (current != null && !sending.any((e) => e['kind'] == 'vehicle' && e['capturedAt'] == current['capturedAt'])) {
      sending.add({...current, 'capturedAt': ServerClock.stamp(now)});
    }
    final attributes = <String, dynamic>{'events': sending, 'gps': ?gps, 'reportedAt': ServerClock.stamp(now)};
    final cursor = await SyncService.cursor();
    final changes = await SyncService.changesCursor();
    try {
      final document = await api.post('/trips/$tripId/reports?${cursor == null ? '' : 'cursor=$cursor&'}changes=$changes', resourceData('trip-reports', attributes: attributes));
      queue.removeRange(0, fromQueue);
      await ServerClock.learn(document.resource.attributes['serverTime']?.toString());
      final live = TripLive.from(document.resource);
      tripInfo['status'] = live.status;
      tripInfo['states'] = {for (final s in live.stops) if (s.state != StopState.waiting) '${s.index}': s.state};
      tripInfo['left'] = [for (final s in live.stops) if (s.left) s.index];
      tripInfo['next'] = live.nextStopIndex;
      tripInfo['vehicle'] = live.vehicleState;
      tripInfo['atStop'] = live.vehicleAtStop;
      tripInfo['sensors'] = live.sensors;
      data['vehicleSpeed'] = live.vehicleSpeed;
      data['sensors'] = live.sensors;
      if (live.itineraryName != null) data['itinerary'] = live.itineraryName;
      data['outbound'] = live.outbound;
      await _vehicle(data, live, tracker);
      // Lo declarado a mano desde la app manda sobre el cálculo; lo que puso el
      // servidor porque el teléfono no enviaba, no: se le reenvía lo calculado.
      if (tracker != null && queue.isEmpty && live.myState != null && (live.myState != tracker.state || (live.myManual && !tracker.manual))) {
        if (live.mySetByServer && tracker.state != null && !tracker.finished) {
          queue.add(workerEvent(tracker.state!, tracker.stopId, now, childIds: childIds));
        } else if (!live.mySetByServer || tracker.state == null) {
          // Puesto a mano desde la app: se respeta hasta un cambio real (docs/11 §11.67).
          tracker.declare(live.myState!, stopId: live.myStopId, at: live.myStateAt, manual: live.myManual);
        }
      }
      final sync = document.meta['sync'];
      if (sync is Map) {
        final notifications = [for (final n in (sync['data'] as List? ?? const [])) Resource.fromJson(Map<String, dynamic>.from(n as Map))];
        final syncMeta = Map<String, dynamic>.from(sync['meta'] as Map? ?? const {});
        // Las notificaciones salen en la cortina (docs/11 §11.63); la app abierta recarga lo que cambió.
        final result = await SyncService.apply(api, notifications, syncMeta);
        FlutterForegroundTask.sendDataToMain({'changed': result.changed.toList(), 'cache': result.cacheChanged});
      }
    } on ApiException catch (error) {
      // Un cambio que el servidor no acepta (422) no se reintenta.
      if (!error.isNetwork && error.statusCode == 422 && queue.isNotEmpty) queue.removeAt(0);
      if (error.statusCode == 404 || error.statusCode == 403) {
        await TripWindow.markDone(tripId, now.subtract(settings.windowAfter));
        await Notifications.tripFinished(tripId);
        await _stop(settings);
        return;
      }
    } catch (_) {
      // Se reintenta en la siguiente vuelta (la cola se guarda).
    }

    // El viaje terminó para él: estado final o fin del viaje. Sigue Y más.
    final status = '${tripInfo['status']}';
    var endedAt = ended;
    if (endedAt == null && queue.isEmpty && ((tracker?.finished ?? false) || status == 'terminado' || status == 'cancelado')) {
      endedAt = now;
      data['endedAt'] = now.toIso8601String();
      await TripWindow.markDone(tripId, now);
    }
    if (status == 'terminado') await Notifications.tripFinished(tripId);

    data['tracker'] = tracker?.toJson();
    // Sin conexión la cola crece: se guardan los cambios del trabajador y las últimas observaciones.
    data['queue'] = trimQueue(queue);
    data['trip'] = tripInfo;
    data['lastAt'] = now.toIso8601String();
    final me = _motion(tracker, data, tripInfo);
    data['me'] = me?.toJson();
    FlutterForegroundTask.sendDataToMain({'nextAt': now.add(settings.shortEvery).toIso8601String(), 'tripId': tripId, 'me': ?me?.toJson()});

    // «Mi estado» (docs/11 §11.63 y §11.65): la parada detectada (en Viajando, ninguna).
    final state = tracker?.state;
    final content = myStateNotice(
      stateName: WorkerState.notice(state),
      state: state,
      itineraryName: data['itinerary']?.toString(),
      outbound: data['outbound'] != false,
      myStop: tracker?.stopName,
      gpsOn: gpsOn,
      alwaysPermission: permission == LocationPermission.always,
      ended: endedAt != null,
    );
    data['tap'] = !gpsOn ? 'gps' : (permission != LocationPermission.always ? 'permiso' : 'trip:$tripId');
    await FlutterForegroundTask.saveData(key: TrackingService._key, value: jsonEncode(data));
    FlutterForegroundTask.updateService(notificationTitle: content.title, notificationText: content.text);
  }

  /// Un cambio guardado en la cola.
  static Map<String, dynamic> _event(Map<String, dynamic> q) => q;

  /// Lo que muestra la tarjeta de estado de «Ver recorrido» (docs/11 §11.67):
  /// antes de Viajando, el movimiento y la velocidad del trabajador; desde
  /// Viajando, los del vehículo (según los sensores).
  static MyMotion? _motion(WorkerTracker? tracker, Map<String, dynamic> data, Map<String, dynamic> tripInfo) {
    if (tracker == null) return null;
    final position = data['position'] is Map ? Map<String, dynamic>.from(data['position'] as Map) : null;
    final travelling = tracker.state == WorkerTracker.travelling;
    final vehicleState = tripInfo['vehicle']?.toString();
    return MyMotion(
      state: tracker.state,
      stopName: tracker.stopName,
      manual: tracker.manual,
      moving: travelling ? (vehicleState == null ? null : vehicleState == 'en_movimiento') : tracker.moving,
      speedKmh: travelling ? (data['vehicleSpeed'] as num?)?.toDouble() : tracker.speedKmh,
      latitude: (position?['lat'] as num?)?.toDouble(),
      longitude: (position?['lon'] as num?)?.toDouble(),
      at: DateTime.tryParse('${position?['at']}'),
    );
  }

  static Future<T> _safe<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }

  /// Notificación del vehículo (docs/11 §11.63): mientras el viaje está en
  /// ejecución y él no llegó a un estado definitivo. Se compone con la línea
  /// del recorrido y solo se vuelve a mostrar si cambia.
  Future<void> _vehicle(Map<String, dynamic> data, TripLive live, WorkerTracker? tracker) async {
    final tripId = '${data['tripId']}';
    final myState = WorkerState.normalize(tracker?.state ?? live.myState);
    final show = live.status == 'en_ejecucion' && !WorkerState.isFinalFor(myState, outbound: live.outbound) && data['endedAt'] == null;
    if (!show) {
      if (data['vehicleSig'] != null) await Notifications.cancel(Notifications.vehicleId(tripId));
      data['vehicleSig'] = null;
      return;
    }
    if (live.vehicleState == 'en_movimiento' || live.nextStopIndex >= 2) data['moved'] = true;
    final view = VehicleView(
      vehicleType: live.vehicleTypeName ?? 'Vehículo',
      itineraryName: live.itineraryName ?? data['itinerary']?.toString(),
      outbound: live.outbound,
      state: live.vehicleState,
      sensors: live.sensors,
      stops: [for (final s in live.stops) s.landmark],
      nextStopIndex: live.nextStopIndex,
      atStop: live.vehicleAtStop,
      movedOnce: data['moved'] == true,
    );
    final lastLines = [for (final l in (data['vehicleLines'] as List? ?? const [])) '$l'];
    final content = vehicleNotice(view, lastLines: lastLines);
    if (!view.noData) data['vehicleLines'] = vehicleStopLines(view).$1;
    final signature = content.toString();
    if (signature == data['vehicleSig']) return;
    data['vehicleSig'] = signature;
    await Notifications.showVehicle(tripId, content);
  }

  /// Primer cálculo: el recorrido con las coordenadas de las paradas (la
  /// parada se detecta por cercanía; docs/11 §11.65).
  Future<WorkerTracker?> _bootstrap(ApiClient api, String tripId, AppSettings settings) async {
    try {
      final live = TripLive.from((await api.get('/trips/$tripId/live')).resource);
      final route = [
        for (final s in live.stops)
          if (s.latitude != null && s.longitude != null) RouteStop(s.stopId, s.landmark, GeoPoint(s.latitude!, s.longitude!)),
      ];
      if (route.length < 2) return null;
      final tracker = WorkerTracker(outbound: live.outbound, route: route, config: trackerConfig(settings));
      if (live.myState != null) tracker.declare(live.myState!, stopId: live.myStopId, at: live.myStateAt, manual: live.myManual);
      return tracker;
    } catch (_) {
      return null;
    }
  }

  Future<void> _stop(AppSettings settings) async {
    await FlutterForegroundTask.removeData(key: TrackingService._key);
    // La próxima ventana (si la hay) queda programada antes de cerrar.
    await TripWindow.reschedule(settings);
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Ajustes del cálculo del estado del trabajador.
TrackerConfig trackerConfig(AppSettings settings) => TrackerConfig(
      stopRadius: settings.distance('radio_parada'),
      approachRadius: settings.distance('radio_acercamiento'),
      gpsTolerance: settings.distance('tolerancia_gps'),
      humanSpeed: settings.speed('velocidad_humana'),
      consecutive: settings.integer('calculos_consecutivos'),
    );

/// Lo que se sabe del viaje (guardado entre vueltas) para el cálculo.
TripInfo tripInfoFrom(Map<String, dynamic> info) => TripInfo(
      status: '${info['status'] ?? 'planificado'}',
      stopStates: {
        for (final e in (info['states'] is Map ? (info['states'] as Map).entries : const <MapEntry>[]))
          if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): '${e.value}',
      },
      left: {for (final i in (info['left'] is List ? info['left'] as List : const [])) (i as num).toInt()},
      nextStopIndex: (info['next'] as num?)?.toInt() ?? 0,
      vehicleState: info['vehicle']?.toString(),
      vehicleAtStop: info['atStop'] == true,
      sensors: (info['sensors'] as num?)?.toInt() ?? 0,
    );

/// Estado, movimiento y última ubicación calculados en el teléfono.
class MyMotion {
  final String? state;
  final String? stopName;
  final bool manual;

  /// En movimiento (true), Detenido (false) o sin datos (null).
  final bool? moving;
  final double? speedKmh;
  final double? latitude;
  final double? longitude;
  final DateTime? at;

  const MyMotion({this.state, this.stopName, this.manual = false, this.moving, this.speedKmh, this.latitude, this.longitude, this.at});

  Map<String, dynamic> toJson() => {
        'state': state,
        'stopName': stopName,
        'manual': manual,
        'moving': moving,
        'speed': speedKmh,
        'lat': latitude,
        'lon': longitude,
        'at': at?.toIso8601String(),
      };

  factory MyMotion.fromJson(Map<String, dynamic> j) => MyMotion(
        state: j['state']?.toString(),
        stopName: j['stopName']?.toString(),
        manual: j['manual'] == true,
        moving: j['moving'] as bool?,
        speedKmh: (j['speed'] as num?)?.toDouble(),
        latitude: (j['lat'] as num?)?.toDouble(),
        longitude: (j['lon'] as num?)?.toDouble(),
        at: DateTime.tryParse('${j['at']}'),
      );
}

/// Cambio de estado del trabajador con su parada detectada y la hora de
/// captura (UTC, con el reloj del servidor; docs/11 §11.67).
Map<String, dynamic> workerEvent(String state, String? stopId, DateTime at, {List<String> childIds = const [], bool manual = false}) => {
      'kind': 'worker',
      'state': state,
      'stopId': ?(stopId == null ? null : int.tryParse(stopId)),
      if ((state == 'viajando' || state == 'en_parada') && childIds.isNotEmpty) 'childIds': [for (final id in childIds) int.tryParse(id) ?? 0],
      if (manual) 'manual': true,
      'capturedAt': ServerClock.stamp(at),
    };

/// Observación del sensor sobre el vehículo, con la velocidad y la hora de captura.
Map<String, dynamic> vehicleEvent(TrackerStep step, DateTime at) => {
      'kind': 'vehicle',
      'vehicleState': step.vehicleState,
      'nextStopIndex': step.nextStopIndex,
      'atStop': step.atStop ?? false,
      'inRadius': step.inRadius ?? false,
      'speed': ?step.speedKmh,
      'capturedAt': ServerClock.stamp(at),
    };

/// La observación cambió (la velocidad sola no cuenta: va con cada envío).
bool sameObservation(Map<String, dynamic> a, Map<String, dynamic> b) =>
    a['vehicleState'] == b['vehicleState'] && a['nextStopIndex'] == b['nextStopIndex'] && a['atStop'] == b['atStop'] && a['inRadius'] == b['inRadius'];

/// Cola sin conexión: todos los cambios del trabajador y, como mucho, las 200
/// últimas observaciones del vehículo (cada una solo cuando cambió).
List<Map<String, dynamic>> trimQueue(List<Map<String, dynamic>> queue, {int maxVehicle = 200}) {
  final vehicles = queue.where((e) => e['kind'] == 'vehicle').length;
  if (vehicles <= maxVehicle) return queue;
  var drop = vehicles - maxVehicle;
  return [
    for (final e in queue)
      if (e['kind'] != 'vehicle' || drop-- <= 0) e,
  ];
}
