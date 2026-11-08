import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../app_settings.dart';
import '../notifications.dart';
import 'worker_tracker.dart';

/// Servicio de ubicación en primer plano durante el viaje (docs/11 §11.41 y
/// §11.43): desde «Anticipación viaje» antes de la salida hasta un estado
/// definitivo. Cada «Frecuencia cálculo» toma la posición, calcula el estado
/// del trabajador (y del vehículo si es sensor) y lo envía con
/// `POST trips/{id}/reports`. Los cambios de estado se guardan en una cola y
/// se reenvían hasta recibir el acuse.
class TrackingService {
  static const _key = 'tracking';

  static void init(Duration interval) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recorrido',
        channelName: 'Viaje en curso',
        channelDescription: 'Se muestra mientras la app usa la ubicación durante un viaje',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(interval.inMilliseconds < 5000 ? 5000 : interval.inMilliseconds),
        allowWakeLock: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

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

  /// Empieza a calcular su estado en [trip]. [stops] en el orden del
  /// itinerario (1.ª → última); [myStopId] su parada.
  static Future<void> start({
    required Trip trip,
    required List<Stop> stops,
    required String myStopId,
    required AppSettings settings,
    List<String> childIds = const [],
  }) async {
    final ordered = trip.outbound ? stops : stops.reversed.toList();
    final route = [for (final s in ordered) RouteStop(s.id, s.landmark, GeoPoint(s.latitude, s.longitude))];
    var myIndex = route.indexWhere((s) => s.id == myStopId);
    if (myIndex < 0) myIndex = trip.outbound ? route.length - 1 : 0;
    if (route.isEmpty) return;

    final existing = await FlutterForegroundTask.getData<String>(key: _key);
    if (existing != null && await isRunning && (jsonDecode(existing) as Map)['tripId'] == trip.id) return;

    final config = TrackerConfig(
      stopRadius: settings.distance('radio_parada'),
      gpsTolerance: settings.distance('tolerancia_gps'),
      humanSpeed: settings.speed('velocidad_humana'),
      abandonDistance: settings.distance('distancia_abandono'),
      consecutive: settings.integer('calculos_consecutivos'),
      finalWait: settings.duration('espera_final'),
    );
    final tracker = WorkerTracker(outbound: trip.outbound, route: route, myIndex: myIndex, config: config);
    await FlutterForegroundTask.saveData(
      key: _key,
      value: jsonEncode({
        'tripId': trip.id,
        'title': '${trip.itineraryName ?? ''} • ${trip.directionName}',
        'departsAt': trip.departsAt.toIso8601String(),
        'maxEnd': trip.departsAt.add(settings.duration('duracion_maxima') + const Duration(hours: 1)).toIso8601String(),
        'tracker': tracker.toJson(),
        'queue': <Map<String, dynamic>>[],
        'childIds': childIds,
        'trip': {'status': trip.status, 'passedMine': false, 'next': 0},
        'sensors': 0,
      }),
    );

    final interval = settings.duration('frecuencia_calculo');
    init(interval);
    if (await isRunning) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.location],
        notificationTitle: 'Viaje: ${trip.itineraryName ?? ''} • ${trip.directionName}',
        notificationText: 'Calculando su estado con la ubicación',
        callback: trackingCallback,
      );
    }
  }

  /// Los hijos que suben con él (se envían al pasar a Viajando o Recogido).
  static Future<void> setChildren(List<String> childIds) async {
    final raw = await FlutterForegroundTask.getData<String>(key: _key);
    if (raw == null) return;
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map)..['childIds'] = childIds;
    await FlutterForegroundTask.saveData(key: _key, value: jsonEncode(data));
  }

  static Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
    await FlutterForegroundTask.removeData(key: _key);
  }
}

@pragma('vm:entry-point')
void trackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingHandler());
}

/// Cada cálculo, en el aislamiento del servicio.
class TrackingHandler extends TaskHandler {
  ApiClient? _api;
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Notifications.init();
    _api = await ApiClient.create();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_busy) return;
    _busy = true;
    _tick().whenComplete(() => _busy = false);
  }

  Future<void> _tick() async {
    final raw = await FlutterForegroundTask.getData<String>(key: TrackingService._key);
    final api = _api;
    if (raw == null || api == null) return;
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final tracker = WorkerTracker.fromJson(Map<String, dynamic>.from(data['tracker'] as Map));
    final queue = [for (final q in data['queue'] as List) Map<String, dynamic>.from(q as Map)];
    final tripInfo = Map<String, dynamic>.from(data['trip'] as Map);
    final tripId = '${data['tripId']}';
    final title = '${data['title']}';
    final now = DateTime.now();

    if (now.isAfter(DateTime.parse('${data['maxEnd']}'))) {
      await _finish(title, 'El viaje ya debió terminar.');
      return;
    }

    TrackerStep? step;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      step = tracker.step(
        GeoPoint(position.latitude, position.longitude),
        now,
        TripInfo(status: '${tripInfo['status']}', vehiclePassedMyStop: tripInfo['passedMine'] == true, nextStopIndex: (tripInfo['next'] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      // Sin señal del GPS en este cálculo: se envía lo pendiente.
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
    }

    // Un informe por cálculo: el primer cambio pendiente y, si es sensor, el vehículo.
    final pending = queue.isEmpty ? null : queue.first;
    final attributes = <String, dynamic>{
      ...?pending,
      'reportedAt': pending?['reportedAt'] ?? now.toIso8601String(),
      if (step != null && step.isSensor) ...{'vehicleState': step.vehicleState, 'nextStopIndex': step.nextStopIndex, 'atStop': step.atStop},
    };
    try {
      final document = await api.post('/trips/$tripId/reports', resourceData('trip-reports', attributes: attributes));
      if (pending != null) queue.removeAt(0);
      final live = TripLive.from(document.resource);
      final mine = live.myStop;
      tripInfo['status'] = live.status;
      tripInfo['passedMine'] = mine != null && mine.passed;
      tripInfo['next'] = live.nextStopIndex;
      data['sensors'] = live.sensors;
      // Lo declarado a mano desde la app (o por otra vía) manda sobre el cálculo.
      if (queue.isEmpty && live.myState != null && live.myState != tracker.state && live.myState != 'de_camino') {
        tracker.declare(live.myState!);
      }
    } on ApiException catch (error) {
      if (!error.isNetwork && pending != null && (error.statusCode == 422 || error.statusCode == 403 || error.statusCode == 404)) queue.removeAt(0);
      if (error.statusCode == 404 || error.statusCode == 403) {
        await _finish(title, 'El viaje ya no está disponible.');
        return;
      }
    } catch (_) {
      // Se reintenta en el siguiente cálculo.
    }

    data['tracker'] = tracker.toJson();
    data['queue'] = queue.length > 50 ? queue.sublist(queue.length - 50) : queue;
    data['trip'] = tripInfo;
    await FlutterForegroundTask.saveData(key: TrackingService._key, value: jsonEncode(data));

    final status = '${tripInfo['status']}';
    if ((tracker.finished || status == 'terminado' || status == 'cancelado') && queue.isEmpty) {
      await _finish(title, status == 'terminado' ? 'Terminó el viaje.' : 'Su estado: ${WorkerState.name(tracker.state)}.');
      return;
    }
    FlutterForegroundTask.updateService(
      notificationTitle: 'Viaje: $title',
      notificationText: '${WorkerState.name(tracker.state)} • ${data['sensors']} sensores',
    );
  }

  Future<void> _finish(String title, String reason) async {
    await Notifications.showDisableGps('$title. $reason Ya no hace falta la ubicación: puede quitar el GPS.');
    await FlutterForegroundTask.removeData(key: TrackingService._key);
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
