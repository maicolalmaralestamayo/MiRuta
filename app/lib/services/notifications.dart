import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/storage.dart';
import 'notification_texts.dart';

/// Notificaciones del teléfono (docs/11 §11.63). Seis canales: Viajes,
/// Vehículo, Mi estado, Solicitudes, Mensajes y Actualizaciones. Todas salen
/// siempre en la cortina (con la app abierta o cerrada) y cada una se va
/// actualizando en su sitio: una por viaje, una del vehículo por viaje, una
/// de solicitudes pendientes, una por solicitud respondida, una de mensajes y
/// una de actualización. «Mi estado» es la notificación fija del servicio de
/// ubicación (TrackingService); aquí solo su sustituta cuando el servicio no
/// puede arrancar.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Lo que se tocó en una notificación ("trip:15", "gestion", "inicio",
  /// "conversation:3", "update", "olvide", "gps", "permiso"). La pantalla
  /// principal lo escucha.
  static final tapped = ValueNotifier<String?>(null);

  // Canales (docs/11 §11.63). Los de la 4.2.0 se borran al abrir la app.
  static const channelTrips = 'miruta_viajes';
  static const channelVehicle = 'miruta_vehiculo';
  static const channelMyState = 'miruta_mi_estado';
  static const channelApplications = 'miruta_solicitudes';
  static const channelMessages = 'miruta_mensajes';
  static const channelUpdates = 'miruta_actualizaciones';
  static const obsoleteChannels = ['viajes', 'ubicacion', 'mi_estado', 'general', 'recorrido'];

  static const _channels = {
    channelTrips: ('Viajes', 'Un aviso por viaje: planificado, cambiado, en ejecución, cancelado o eliminado', Importance.high),
    channelVehicle: ('Vehículo', 'Dónde va el vehículo del viaje en ejecución', Importance.defaultImportance),
    channelMyState: ('Mi estado', 'Su estado en el viaje mientras MiRuta usa la ubicación', Importance.defaultImportance),
    channelApplications: ('Solicitudes', 'Solicitudes pendientes y respuestas a las suyas', Importance.high),
    channelMessages: ('Mensajes', 'Respuestas del desarrollador', Importance.high),
    channelUpdates: ('Actualizaciones', 'Versiones nuevas de MiRuta', Importance.defaultImportance),
  };

  // Identificadores fijos y por rango.
  static const idUpdate = 7;
  static const idMyState = 9;
  static const idPending = 11;
  static const idMessages = 12;
  static int tripId(String id) => 100000000 + _num(id);
  static int vehicleId(String id) => 200000000 + _num(id);
  static int resolvedId(String id) => 300000000 + _num(id);
  static int _num(String id) => (int.tryParse(id) ?? id.hashCode.abs()) % 99999999;

  static const _tripsKey = 'user.notices.trips';
  static const _resolvedKey = 'user.notices.resolved';
  static const _pendingKey = 'user.notices.pending';
  static const _repliesKey = 'user.notices.replies';
  static const _updateKey = 'user.notices.update';

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

  /// Crea los seis canales y borra los de la 4.2.0 (al abrir la app).
  static Future<void> setupChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final e in _channels.entries) {
      try {
        await android.createNotificationChannel(AndroidNotificationChannel(e.key, e.value.$1, description: e.value.$2, importance: e.value.$3));
      } catch (_) {}
    }
    // Recordatorios «Active la ubicación» que programó la 4.2.0 (ya no existen).
    try {
      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.id >= 100000 && pending.id < 200000) await _plugin.cancel(id: pending.id);
      }
    } catch (_) {}
    for (final id in obsoleteChannels) {
      try {
        await android.deleteNotificationChannel(channelId: id);
      } catch (_) {
        // Un canal en uso por el servicio en primer plano no se puede borrar.
      }
    }
  }

  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static AndroidNotificationDetails _details(String channel, NoticeContent c, {int? timeoutAfter, bool onlyAlertOnce = false, bool ongoing = false}) {
    final (name, description, importance) = _channels[channel]!;
    return AndroidNotificationDetails(
      channel,
      name,
      channelDescription: description,
      importance: importance,
      priority: importance == Importance.high ? Priority.high : Priority.defaultPriority,
      // Todas las líneas a la vista; la destacada en naranja (formato HTML de Android).
      styleInformation: BigTextStyleInformation(
        noticeHtml(c),
        htmlFormatBigText: true,
        contentTitle: htmlEscape(c.title),
        htmlFormatContentTitle: true,
        htmlFormatContent: true,
        htmlFormatTitle: true,
      ),
      timeoutAfter: timeoutAfter,
      onlyAlertOnce: onlyAlertOnce,
      ongoing: ongoing,
      ticker: c.title,
      subText: name,
    );
  }

  static Future<void> _show(int id, String channel, NoticeContent c, {String? payload, int? timeoutAfter, bool onlyAlertOnce = false}) async {
    try {
      final body = c.lines.isNotEmpty ? htmlEscape(c.lines.first) : (c.highlight == null ? '' : htmlEscape(c.highlight!));
      await _plugin.show(
        id: id,
        title: htmlEscape(c.title),
        body: body,
        notificationDetails: NotificationDetails(android: _details(channel, c, timeoutAfter: timeoutAfter, onlyAlertOnce: onlyAlertOnce)),
        payload: payload,
      );
    } catch (_) {
      // Fuera de Android (pruebas) o sin permiso de notificaciones.
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  static String? payloadOf(String kind, Map<String, dynamic> data) {
    final tripId = data['tripId']?.toString();
    return switch (kind) {
      'solicitud_recibida' => 'gestion',
      'solicitud_resuelta' => 'inicio',
      'respuesta_desarrollador' => 'conversation:${data['conversationId'] ?? ''}',
      'olvide_recibida' => 'olvide',
      _ => tripId == null ? null : 'trip:$tripId',
    };
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  /// Estado de la notificación del viaje según la del servidor.
  static String? tripNoticeStatusOf(String kind, Map<String, dynamic> data) => switch (kind) {
        'viaje_creado' => 'planificado',
        'viaje_modificado' => 'cambiado',
        'viaje_eliminado' => 'eliminado',
        'viaje_estado' => '${data['status'] ?? ''}',
        _ => null,
      };

  /// Notificación de GET sync según su `kind` (docs/13 §13.10). Siempre en
  /// la cortina (docs/11 §11.63).
  static Future<void> showServer(String kind, String title, String body, Map<String, dynamic> data) async {
    switch (kind) {
      case 'viaje_creado' || 'viaje_modificado' || 'viaje_estado' || 'viaje_eliminado':
        return _showTrip(kind, title, body, data);
      case 'vehiculo_en_parada' || 'vehiculo_detencion_larga' || 'vehiculo_reanuda':
        // La del vehículo la compone el teléfono con la línea del recorrido.
        return;
      case 'solicitud_recibida' || 'olvide_recibida':
        // Se muestra (y actualiza) la única de «N solicitudes pendientes».
        await Storage.setString(_pendingKey, null);
        return;
      case 'solicitud_resuelta':
        return _showResolved(data);
      case 'respuesta_desarrollador':
        return _showReply(body, data);
    }
    await _show(DateTime.now().millisecondsSinceEpoch % 100000 + 1000, channelApplications, NoticeContent(title, [body]), payload: payloadOf(kind, data));
  }

  static Future<void> _showTrip(String kind, String title, String body, Map<String, dynamic> data) async {
    final id = data['tripId']?.toString();
    final status = tripNoticeStatusOf(kind, data);
    if (id == null || status == null || status == 'terminado') {
      if (id != null && status == 'terminado') await tripFinished(id);
      return;
    }
    final departsAt = _date(data['departsAt']);
    final content = data['itineraryName'] == null && departsAt == null
        ? NoticeContent(title, [body])
        : tripNotice(
            status: status,
            itineraryName: data['itineraryName']?.toString(),
            direction: '${data['direction'] ?? 'ida'}',
            departsAt: departsAt,
            departureStop: data['departureStop']?.toString(),
            vehicleType: data['vehicleType']?.toString(),
            changes: [for (final c in (data['changes'] as List? ?? const [])) '$c'],
          );
    // Cancelado o eliminado: se quita sola al pasar la hora de salida.
    int? timeout;
    if (status == 'cancelado' || status == 'eliminado') {
      if (departsAt == null || !departsAt.isAfter(DateTime.now())) {
        await cancel(tripId(id));
        return;
      }
      timeout = departsAt.difference(DateTime.now()).inMilliseconds;
    }
    await _show(tripId(id), channelTrips, content, payload: status == 'eliminado' ? null : 'trip:$id', timeoutAfter: timeout);
    final trips = await Storage.getJson(_tripsKey);
    trips[id] = {'status': status, 'departsAt': departsAt?.toIso8601String()};
    while (trips.length > 40) {
      trips.remove(trips.keys.first);
    }
    await Storage.setJson(_tripsKey, trips);
  }

  /// El viaje terminó: se quitan su notificación y la del vehículo.
  static Future<void> tripFinished(String id) async {
    await cancel(tripId(id));
    await cancel(vehicleId(id));
    final trips = await Storage.getJson(_tripsKey);
    if (trips.remove(id) != null) await Storage.setJson(_tripsKey, trips);
  }

  static Future<void> _showResolved(Map<String, dynamic> data) async {
    final id = data['applicationId']?.toString();
    if (id == null) return;
    final content = resolvedApplicationNotice(
      approved: data['status'] == 'aprobada',
      type: '${data['type'] ?? 'entidad'}',
      entity: data['entity']?.toString(),
      itinerary: data['itinerary']?.toString(),
      stop: data['stop']?.toString(),
      resolvedAt: _date(data['resolvedAt']),
      reason: data['reason']?.toString(),
      note: data['note']?.toString(),
    );
    await _show(resolvedId(id), channelApplications, content, payload: 'inicio');
    final ids = await Storage.getJson(_resolvedKey);
    ids[id] = true;
    await Storage.setJson(_resolvedKey, ids);
  }

  /// Vio sus solicitudes respondidas en Inicio: se quitan sus notificaciones.
  static Future<void> resolvedSeen() async {
    final ids = await Storage.getJson(_resolvedKey);
    for (final id in ids.keys) {
      await cancel(resolvedId(id));
    }
    if (ids.isNotEmpty) await Storage.setJson(_resolvedKey, {});
  }

  static Future<void> _showReply(String body, Map<String, dynamic> data) async {
    final state = await Storage.getJson(_repliesKey);
    final unread = ((state['unread'] as num?)?.toInt() ?? 0) + 1;
    await Storage.setJson(_repliesKey, {'unread': unread});
    await _show(idMessages, channelMessages, developerReplyNotice(text: body, sentAt: _date(data['sentAt']) ?? DateTime.now(), unread: unread),
        payload: 'conversation:${data['conversationId'] ?? ''}');
  }

  /// Leyó la conversación: se quita la de mensajes.
  static Future<void> messagesRead() async {
    await cancel(idMessages);
    await Storage.setJson(_repliesKey, {});
  }

  /// Lo que trae el meta de cada consulta (docs/11 §11.63): solicitudes
  /// pendientes, respuestas ya vistas, mensajes ya leídos y viajes terminados
  /// o cuya salida ya pasó (cancelados o eliminados).
  static Future<void> applyMeta(Map<String, dynamic> meta, Map<String, int> counters) async {
    // Solicitudes pendientes: una sola, que cambia con las cantidades.
    final pending = meta['pendingApplications'];
    if (pending is Map) {
      int n(String k) => (pending[k] as num?)?.toInt() ?? 0;
      final content = pendingApplicationsNotice(entity: n('entity'), itinerary: n('itinerary'), accessRecovery: n('accessRecovery'));
      final signature = '${n('entity')},${n('itinerary')},${n('accessRecovery')}';
      if (content == null) {
        await cancel(idPending);
        await Storage.setString(_pendingKey, null);
      } else if (await Storage.getString(_pendingKey) != signature) {
        final onlyRecoveries = n('entity') + n('itinerary') == 0;
        await _show(idPending, channelApplications, content, payload: onlyRecoveries ? 'olvide' : 'gestion');
        await Storage.setString(_pendingKey, signature);
      }
    }
    if (counters['applicationsResolvedUnseen'] == 0) await resolvedSeen();
    if (counters['conversationsUnread'] == 0 && (await Storage.getJson(_repliesKey)).isNotEmpty) await messagesRead();

    for (final id in (meta['finishedTrips'] as List? ?? const [])) {
      await tripFinished('$id');
    }
    // Cancelados o eliminados cuya salida ya pasó (por si el sistema no la quitó).
    final trips = await Storage.getJson(_tripsKey);
    final now = DateTime.now();
    final expired = [
      for (final e in trips.entries)
        if (e.value is Map && ((e.value as Map)['status'] == 'cancelado' || (e.value as Map)['status'] == 'eliminado') &&
            (DateTime.tryParse('${(e.value as Map)['departsAt']}')?.isBefore(now) ?? true))
          e.key,
    ];
    for (final id in expired) {
      await cancel(tripId(id));
      trips.remove(id);
    }
    if (expired.isNotEmpty) await Storage.setJson(_tripsKey, trips);
  }

  /// «Actualización disponible / obligatoria»: una sola; se vuelve a mostrar
  /// con cada versión nueva o si pasa a ser obligatoria.
  static Future<bool> updateShown(int versionCode, bool mandatory) async => await Storage.getString(_updateKey) == '$versionCode:$mandatory';

  static Future<void> showUpdate(String versionName, {required int versionCode, bool mandatory = false, String? size}) async {
    final signature = '$versionCode:$mandatory';
    await _show(idUpdate, channelUpdates, updateNotice(versionName: versionName, mandatory: mandatory, size: size), payload: 'update');
    await Storage.setString(_updateKey, signature);
  }

  /// Ya tiene instalada la última versión.
  static Future<void> cancelUpdate() async {
    if (await Storage.getString(_updateKey) == null) return;
    await cancel(idUpdate);
    await Storage.setString(_updateKey, null);
  }

  /// Notificación del vehículo del viaje (la compone el servicio de ubicación).
  static Future<void> showVehicle(String trip, NoticeContent content) =>
      _show(vehicleId(trip), channelVehicle, content, payload: 'trip:$trip', onlyAlertOnce: true);

  /// «Mi estado» cuando el servicio de ubicación no puede arrancar (sin
  /// permiso de ubicación): notificación normal con el mismo formato
  /// (docs/11 §11.63). [at] la programa para el inicio de la ventana.
  static Future<void> showMyStateFallback(NoticeContent content, {required String payload, DateTime? at}) async {
    try {
      final details = NotificationDetails(android: _details(channelMyState, content));
      final body = content.lines.isNotEmpty ? htmlEscape(content.lines.first) : (content.highlight ?? '');
      await _plugin.cancel(id: idMyState);
      if (at != null && at.isAfter(DateTime.now())) {
        await _plugin.zonedSchedule(
          id: idMyState,
          title: htmlEscape(content.title),
          body: body,
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } else {
        await _plugin.show(id: idMyState, title: htmlEscape(content.title), body: body, notificationDetails: details, payload: payload);
      }
    } catch (_) {}
  }

  static Future<void> cancelMyStateFallback() => cancel(idMyState);

  static Future<void> cancelAll() => _plugin.cancelAll();
}
