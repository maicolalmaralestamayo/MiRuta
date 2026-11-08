import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notificaciones del teléfono (docs/11 §11.37, §11.47 y §11.50). No hay
/// pantalla de avisos: todo lo que la app avisa va por aquí.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Lo que se tocó en una notificación ("trip:15", "gestion",
  /// "conversation:3", "update"). La pantalla principal lo escucha.
  static final tapped = ValueNotifier<String?>(null);

  static const _trips = AndroidNotificationDetails('viajes', 'Viajes',
      channelDescription: 'Viajes planificados, cambios y estado del vehículo', importance: Importance.high, priority: Priority.high);
  static const _location = AndroidNotificationDetails('ubicacion', 'Ubicación',
      channelDescription: 'Recordatorios de activar y de quitar la ubicación (GPS)', importance: Importance.high, priority: Priority.high);
  static const _states = AndroidNotificationDetails('mi_estado', 'Mi estado en el viaje',
      channelDescription: 'Sus propios estados durante el viaje', importance: Importance.defaultImportance);
  static const _general = AndroidNotificationDetails('general', 'Solicitudes y mensajes',
      channelDescription: 'Solicitudes, respuestas del desarrollador y actualizaciones de la app', importance: Importance.defaultImportance);

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      // Se queda en UTC si no se conoce la zona del teléfono.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (response) => tapped.value = response.payload,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) tapped.value = launch!.notificationResponse?.payload;
    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static final _random = Random();

  static int _id() => _random.nextInt(1 << 30);

  /// Notificación de GET sync según su `kind` (docs/13 §13.10).
  static Future<void> showServer(String kind, String title, String body, Map<String, dynamic> data) {
    final tripId = data['tripId']?.toString();
    final payload = switch (kind) {
      'solicitud_recibida' || 'solicitud_resuelta' => 'gestion',
      'respuesta_desarrollador' => 'conversation:${data['conversationId'] ?? ''}',
      'olvide_recibida' => 'olvide',
      _ => tripId == null ? null : 'trip:$tripId',
    };
    final details = kind.startsWith('viaje') || kind.startsWith('vehiculo') ? _trips : _general;
    return _plugin.show(id: _id(), title: title, body: body, notificationDetails: NotificationDetails(android: details), payload: payload);
  }

  /// «Actualización disponible» (docs/11 §11.50).
  static Future<void> showUpdate(String versionName, {bool mandatory = false}) => _plugin.show(
        id: 7,
        title: mandatory ? 'Actualización obligatoria' : 'Actualización disponible',
        body: 'Ya está la versión $versionName de MiRuta. ${mandatory ? 'Instálela para seguir usando la app.' : 'Puede instalarla desde Más.'}',
        notificationDetails: const NotificationDetails(android: _general),
        payload: 'update',
      );

  static int _reminderId(String tripId) => 100000 + (int.tryParse(tripId) ?? tripId.hashCode.abs() % 100000);

  /// Recordatorio de activar la ubicación «Anticipación viaje» antes de la
  /// salida (docs/11 §11.41). Lo programa el propio teléfono.
  static Future<void> scheduleLocationReminder({required String tripId, required DateTime at, required String body}) async {
    await _plugin.cancel(id: _reminderId(tripId));
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _reminderId(tripId),
      title: 'Active la ubicación',
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(android: _location),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'trip:$tripId',
    );
  }

  static Future<void> cancelLocationReminder(String tripId) => _plugin.cancel(id: _reminderId(tripId));

  /// Al llegar a un estado definitivo o al terminar el viaje.
  static Future<void> showDisableGps(String body) => _plugin.show(
        id: 8,
        title: 'Ya puede quitar la ubicación',
        body: body,
        notificationDetails: const NotificationDetails(android: _location),
      );

  /// Sus propios estados (docs/11 §11.47).
  static Future<void> showMyState(String tripId, String title, String body) => _plugin.show(
        id: 9,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _states),
        payload: 'trip:$tripId',
      );

  static Future<void> cancelAll() => _plugin.cancelAll();
}
