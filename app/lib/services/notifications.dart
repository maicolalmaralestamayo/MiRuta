import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'templates.dart';
import 'user_settings.dart';

/// Notificaciones locales: avisos de salida y regreso programados, cambios,
/// paso por paradas, mensajes y avisos del servidor.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _trips = AndroidNotificationDetails('trips', 'Viajes',
      channelDescription: 'Avisos de salida y regreso', importance: Importance.high, priority: Priority.high);
  static const _changes = AndroidNotificationDetails('changes', 'Cambios en los viajes',
      channelDescription: 'Cancelaciones y cambios de chofer, transporte u horario', importance: Importance.high, priority: Priority.high);
  static const _route = AndroidNotificationDetails('route', 'Recorrido',
      channelDescription: 'Paso del transporte por las paradas', importance: Importance.high, priority: Priority.high);
  static const _messages = AndroidNotificationDetails('messages', 'Mensajes y avisos',
      channelDescription: 'Chats, solicitudes y avisos', importance: Importance.defaultImportance);

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      // Se queda en UTC si no se conoce la zona del teléfono.
    }
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  static int _tripId(Trip trip, int kind) => (int.tryParse(trip.id) ?? trip.id.hashCode) * 10 + kind;

  /// Programa (o reprograma) los avisos de salida y regreso de un viaje
  /// confirmado (docs/07-algoritmos.md §7.16).
  static Future<void> scheduleTrip(Trip trip, UserSettings settings, {Map<String, Stop> stops = const {}, bool absent = false}) async {
    await cancelTrip(trip);
    if (!trip.isConfirmed) return;
    if (absent && !settings.boolean('notify_during_absence', false)) return;

    final variables = tripVariables(trip, stops: stops);
    for (final kind in ['departure', 'return']) {
      final event = kind == 'departure' ? trip.departsAt : trip.returnsAt;
      final at = noticeTime(event, kind, settings);
      if (at == null || !at.isAfter(DateTime.now())) continue;

      final defaultTemplate = kind == 'departure'
          ? 'Salida {fecha_salida} a las {hora_salida} desde {punto_salida}.'
          : 'Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.';
      await _plugin.zonedSchedule(
        id: _tripId(trip, kind == 'departure' ? 1 : 2),
        title: kind == 'departure' ? 'Salida: ${trip.itineraryName ?? ''}' : 'Regreso: ${trip.itineraryName ?? ''}',
        body: renderTemplate(settings.string('${kind}_notice_template', defaultTemplate), variables),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(android: _trips),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'trip:${trip.id}',
      );
    }
  }

  /// Momento del aviso según el ajuste del usuario; null si no hay que avisar.
  @visibleForTesting
  static DateTime? noticeTime(DateTime event, String kind, UserSettings settings) {
    if (settings.string('${kind}_notice_mode', 'relative') == 'fixed') {
      final parts = settings.string('${kind}_notice_fixed_time', kind == 'departure' ? '14:00' : '23:00').split(':');
      final day = event.subtract(Duration(days: settings.integer('${kind}_notice_fixed_days_before', kind == 'departure' ? 0 : 1)));
      final at = DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
      if (!at.isAfter(event)) return at;
      if (settings.string('${kind}_notice_fallback', 'default') == 'none') return null;
      return event.subtract(const Duration(hours: 1));
    }
    return event.subtract(Duration(minutes: settings.integer('${kind}_notice_minutes_before', 60)));
  }

  static Future<void> cancelTrip(Trip trip) async {
    await _plugin.cancel(id: _tripId(trip, 1));
    await _plugin.cancel(id: _tripId(trip, 2));
  }

  static Future<void> cancelAll() => _plugin.cancelAll();

  static final _random = Random();

  static Future<void> showChange(String title, String body, {String? payload}) =>
      _plugin.show(id: _random.nextInt(1 << 30), title: title, body: body, notificationDetails: const NotificationDetails(android: _changes), payload: payload);

  static Future<void> showRoute(String title, String body) =>
      _plugin.show(id: _random.nextInt(1 << 30), title: title, body: body, notificationDetails: const NotificationDetails(android: _route));

  static Future<void> showMessage(String title, String body, {String? payload}) =>
      _plugin.show(id: _random.nextInt(1 << 30), title: title, body: body, notificationDetails: const NotificationDetails(android: _messages), payload: payload);
}
