import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/json_api.dart';
import '../models/models.dart';
import 'notifications.dart';
import 'templates.dart';
import 'user_settings.dart';

/// Recorrido en segundo plano (servicio en primer plano de Android con su
/// notificación fija): envía la ubicación si el usuario es sensor, guarda las
/// posiciones sin cobertura y avisa del paso por las paradas.
class TrackingService {
  static void init({int intervalSeconds = 10}) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tracking',
        channelName: 'Recorrido en curso',
        channelDescription: 'Se muestra mientras sigues un recorrido o compartes tu ubicación',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.repeat(intervalSeconds * 1000), allowWakeLock: true),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// Empieza a seguir un trayecto.
  static Future<void> start({
    required TripLeg leg,
    required Trip trip,
    required List<Stop> orderedStops,
    required String? myStopId,
    required bool share,
    required bool iAmDriver,
    required UserSettings settings,
  }) async {
    final interval = share
        ? settings.integer('location_interval_seconds', 10)
        : settings.integer('tracking_poll_background_seconds', 60);

    await FlutterForegroundTask.saveData(key: 'state', value: jsonEncode({
      'legId': leg.id,
      'tripId': trip.id,
      'direction': leg.direction,
      'itinerary': trip.itineraryName ?? '',
      'stopOrder': orderedStops.map((s) => s.id).toList(),
      'stopNames': {for (final s in orderedStops) s.id: s.landmark},
      'myStopId': myStopId,
      'share': share,
      'iAmDriver': iAmDriver,
      'passed': leg.stopPasses.map((p) => p.stopId).toList(),
      'queue': <Map<String, dynamic>>[],
    }));

    init(intervalSeconds: interval);

    final title = share ? 'Compartiendo ubicación del recorrido' : 'Siguiendo el recorrido';
    if (await isRunning) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.location, ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: '${trip.itineraryName ?? ''} · ${leg.directionLabel}',
        callback: trackingCallback,
      );
    }
  }

  static Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
  }

  /// Cambia si se comparte la ubicación sin reiniciar el seguimiento.
  static Future<void> setSharing(bool share) async {
    final raw = await FlutterForegroundTask.getData<String>(key: 'state');
    if (raw == null) return;
    final state = Map<String, dynamic>.from(jsonDecode(raw) as Map)..['share'] = share;
    await FlutterForegroundTask.saveData(key: 'state', value: jsonEncode(state));
  }
}

@pragma('vm:entry-point')
void trackingCallback() {
  FlutterForegroundTask.setTaskHandler(_TrackingHandler());
}

class _TrackingHandler extends TaskHandler {
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
    final raw = await FlutterForegroundTask.getData<String>(key: 'state');
    final api = _api;
    if (raw == null || api == null) return;
    final state = Map<String, dynamic>.from(jsonDecode(raw) as Map);

    if (state['share'] == true) await _sendPosition(api, state);

    try {
      final leg = TripLeg.from((await api.get('/trip-legs/${state['legId']}')).resource);
      await _handlePasses(leg, state);

      if (!leg.isActive) {
        await Notifications.showRoute('Terminó el recorrido', '${state['itinerary']} · ${leg.directionLabel}');
        await FlutterForegroundTask.saveData(key: 'state', value: jsonEncode(state));
        await FlutterForegroundTask.stopService();
        return;
      }

      final next = _nextStop(state);
      FlutterForegroundTask.updateService(
        notificationText: '${leg.activeSensors} sensor(es)${next == null ? '' : ' · próxima: $next'}',
      );
    } on ApiException {
      // Sin conexión: se reintenta en la siguiente vuelta.
    }

    await FlutterForegroundTask.saveData(key: 'state', value: jsonEncode(state));
  }

  Future<void> _sendPosition(ApiClient api, Map<String, dynamic> state) async {
    final queue = List<Map<String, dynamic>>.from((state['queue'] as List).map((e) => Map<String, dynamic>.from(e as Map)));

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      queue.add({
        'op': 'add',
        'data': resourceData('trip-positions', attributes: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracyM': position.accuracy,
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
        }, relationships: {'tripLeg': ResourceId('trip-legs', state['legId'] as String)})['data'],
      });
    } catch (_) {
      // Sin señal GPS en esta vuelta.
    }

    if (queue.isEmpty) return;

    try {
      if (queue.length == 1) {
        await api.post('/trip-positions', {'data': queue.first['data']});
      } else {
        await api.atomicOperations(queue);
      }
      queue.clear();
    } on ApiException catch (error) {
      if (error.hasCode('LEG_NOT_ACTIVE') || error.hasCode('FORBIDDEN')) {
        queue.clear();
        state['share'] = false;
      }
      // Si es un error de red, se guardan y se envían después.
    }

    state['queue'] = queue.length > 500 ? queue.sublist(queue.length - 500) : queue;
  }

  /// Avisos de paso por paradas (7.20) y parada automática del sensor (7.24).
  Future<void> _handlePasses(TripLeg leg, Map<String, dynamic> state) async {
    final known = List<String>.from(state['passed'] as List);
    final newPasses = leg.stopPasses.where((p) => !known.contains(p.stopId)).toList();
    if (newPasses.isEmpty) return;

    final settings = await UserSettings.cached();
    final order = List<String>.from(state['stopOrder'] as List);
    final ordered = state['direction'] == 'return' ? order.reversed.toList() : order;
    final names = Map<String, dynamic>.from(state['stopNames'] as Map);
    final myStop = state['myStopId'] as String?;
    final mine = myStop == null ? -1 : ordered.indexOf(myStop);
    final scope = settings.string('stop_notice_scope', 'previous');

    for (final pass in newPasses) {
      known.add(pass.stopId);
      final index = ordered.indexOf(pass.stopId);
      if (mine < 0 || index < 0 || scope == 'none' || state['iAmDriver'] == true) continue;

      int? remaining;
      if (index < mine && (scope == 'all' || index == mine - 1)) {
        remaining = mine - index;
      } else if (index >= mine && state['direction'] == 'return' && settings.boolean('stop_notice_after_boarding', false)) {
        remaining = 0;
      }

      if (remaining != null) {
        await Notifications.showRoute(
          'El transporte pasó por ${names[pass.stopId] ?? 'una parada'}',
          renderTemplate(settings.string('stop_notice_template', 'El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la tuya.'), {
            'parada': '${names[pass.stopId] ?? ''}',
            'hora': formatTime(pass.passedAt),
            'paradas_restantes': '$remaining',
            'itinerario': '${state['itinerary']}',
          }),
        );
      }

      // En la salida, el trabajador se baja en su parada y deja de ser sensor.
      if (state['iAmDriver'] != true && state['direction'] == 'outbound' && pass.stopId == myStop) {
        state['share'] = false;
      }
    }

    state['passed'] = known;
  }

  String? _nextStop(Map<String, dynamic> state) {
    final order = List<String>.from(state['stopOrder'] as List);
    final ordered = state['direction'] == 'return' ? order.reversed.toList() : order;
    final passed = List<String>.from(state['passed'] as List);
    final names = Map<String, dynamic>.from(state['stopNames'] as Map);
    for (final id in ordered) {
      if (!passed.contains(id)) return '${names[id] ?? ''}';
    }
    return null;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
