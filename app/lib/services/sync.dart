import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/models.dart';
import 'notifications.dart';
import 'templates.dart';
import 'user_settings.dart';

/// Sincronización de viajes, avisos y mensajes, con detección de cambios
/// (docs/07-algoritmos.md §7.15). Se usa con la app abierta y en segundo plano.
class SyncService {
  static const _tripsKey = 'user.trips';
  static const _stopsKey = 'user.stops';
  static const _lastSyncKey = 'user.last_sync';
  static const _lastNoticeKey = 'user.last_notice';
  static const _conversationsKey = 'user.conversations_seen';
  static const meKey = 'user.me';

  static const tripInclude = 'itinerary,vehicle.vehicleType,driver.worker';

  /// Guarda los datos del usuario que necesitan las tareas en segundo plano.
  static Future<void> rememberMe(Worker me) => Storage.setJson(meKey, {
        'id': me.id,
        'itineraryId': me.itineraryId,
        'stopId': me.stopId,
        'driverId': me.roles.driverId,
      });

  static Future<Map<String, dynamic>> cachedMe() => Storage.getJson(meKey);

  /// Viajes guardados en el teléfono (los del itinerario propio y los que conduce).
  static Future<List<Trip>> cachedTrips() async {
    final json = await Storage.getJson(_tripsKey);
    final trips = json.values.map((value) => Trip.fromJson(Map<String, dynamic>.from(value as Map))).toList();
    trips.sort((a, b) => a.departsAt.compareTo(b.departsAt));
    return trips;
  }

  static Future<Map<String, Stop>> cachedStops() async {
    final json = await Storage.getJson(_stopsKey);
    return json.map((key, value) => MapEntry(key, Stop.fromJson(Map<String, dynamic>.from(value as Map))));
  }

  static Future<void> run(ApiClient api, {bool notifyChanges = true}) async {
    final me = await cachedMe();
    if (me['id'] == null) return;

    final settings = await UserSettings.refresh(api).catchError((_) => UserSettings.cached());
    await _syncStops(api, me['itineraryId'] as String?);
    await _syncTrips(api, me, settings, notifyChanges);
    await _syncNotices(api);
    await _syncConversations(api);
  }

  static Future<void> _syncStops(ApiClient api, String? itineraryId) async {
    if (itineraryId == null) return;
    final stops = await api.getAll('/stops', query: {'filter[itinerary]': itineraryId});
    await Storage.setJson(_stopsKey, {for (final r in stops) r.id: Stop.from(r).toJson()});
  }

  static bool _isMine(Trip trip, Map<String, dynamic> me) =>
      trip.itineraryId == me['itineraryId'] || (me['driverId'] != null && trip.driverId == me['driverId']);

  static Future<void> _syncTrips(ApiClient api, Map<String, dynamic> me, UserSettings settings, bool notifyChanges) async {
    final lastSync = await Storage.getString(_lastSyncKey);
    final query = <String, dynamic>{'include': tripInclude, 'sort': 'updatedAt'};
    if (lastSync != null) {
      query['filter[updatedSince]'] = lastSync;
    } else {
      query['filter[from]'] = DateTime.now().subtract(const Duration(days: 2)).toIso8601String().substring(0, 10);
    }

    final resources = await api.getAll('/trips', query: query);
    final cache = await Storage.getJson(_tripsKey);
    final stops = await cachedStops();
    final absences = await _myAbsences(api);
    String? newest = lastSync;

    for (final resource in resources) {
      final trip = Trip.from(resource);
      if (trip.updatedAt != null) newest = trip.updatedAt!.toUtc().toIso8601String();
      if (!_isMine(trip, me)) continue;

      final previousJson = cache[trip.id];
      final previous = previousJson == null ? null : Trip.fromJson(Map<String, dynamic>.from(previousJson as Map));
      final absent = absences.any((range) => !trip.departsAt.isBefore(range.$1) && trip.departsAt.isBefore(range.$2));

      if (notifyChanges && previous != null) {
        await _notifyChange(previous, trip, settings, stops);
      }

      if (trip.isConfirmed) {
        await Notifications.scheduleTrip(trip, settings, stops: stops, absent: absent);
      } else {
        await Notifications.cancelTrip(trip);
      }

      cache[trip.id] = trip.toJson();
    }

    // Se olvidan los viajes con más de una semana.
    final limit = DateTime.now().subtract(const Duration(days: 7));
    cache.removeWhere((_, value) => DateTime.parse((value as Map)['returnsAt'] as String).isBefore(limit));

    await Storage.setJson(_tripsKey, cache);
    if (newest != null) await Storage.setString(_lastSyncKey, newest);
  }

  static Future<void> _notifyChange(Trip previous, Trip trip, UserSettings settings, Map<String, Stop> stops) async {
    final variables = tripVariables(trip, stops: stops);
    final title = trip.itineraryName ?? 'Tu viaje';

    if (previous.status == TripStatus.confirmed && trip.status == TripStatus.cancelled) {
      await Notifications.showChange('Viaje cancelado', renderTemplate(settings.string('cancel_notice_template', 'Se canceló tu viaje de {itinerario} del {fecha_salida}.'), variables), payload: 'trip:${trip.id}');
      return;
    }

    if (previous.status == TripStatus.confirmed && trip.status == TripStatus.unconfirmed) {
      await Notifications.showChange('Viaje pendiente de confirmación', '$title del ${formatDate(trip.departsAt)}: el viaje está pendiente de confirmación.', payload: 'trip:${trip.id}');
      return;
    }

    if (!trip.isConfirmed || previous.status != TripStatus.confirmed) return;

    final changes = <String>[
      if (previous.driverId != trip.driverId) 'chofer: ${trip.driverName ?? ''}',
      if (previous.vehicleId != trip.vehicleId) 'transporte: ${trip.vehicleTypeName ?? ''} ${trip.vehiclePlate ?? ''}',
      if (!previous.departsAt.isAtSameMomentAs(trip.departsAt)) 'salida: ${formatDateTime(trip.departsAt)}',
      if (!previous.returnsAt.isAtSameMomentAs(trip.returnsAt)) 'regreso: ${formatDateTime(trip.returnsAt)}',
      if (previous.departureStopId != trip.departureStopId) 'punto de salida: ${stops[trip.departureStopId]?.landmark ?? ''}',
      if (previous.returnStopId != trip.returnStopId) 'punto de regreso: ${stops[trip.returnStopId]?.landmark ?? ''}',
    ];

    if (changes.isNotEmpty) {
      variables['cambios'] = changes.join(', ');
      await Notifications.showChange('Cambió tu viaje', renderTemplate(settings.string('change_notice_template', 'Cambió tu viaje de {itinerario} del {fecha_salida}: {cambios}.'), variables), payload: 'trip:${trip.id}');
    }
  }

  /// Ausencias aprobadas propias, como rangos [inicio, fin + 1 día).
  static Future<List<(DateTime, DateTime)>> _myAbsences(ApiClient api) async {
    final resources = await api.getAll('/applications', query: {'filter[mine]': 'true', 'filter[type]': 'absence', 'filter[status]': 'approved'});
    return resources
        .where((r) => r.string('startsOn') != null)
        .map((r) => (DateTime.parse(r.string('startsOn')!), DateTime.parse(r.string('endsOn')!).add(const Duration(days: 1))))
        .toList();
  }

  static Future<void> _syncNotices(ApiClient api) async {
    final since = await Storage.getString(_lastNoticeKey);
    final query = <String, dynamic>{'filter[unread]': 'true', 'sort': 'createdAt'};
    if (since != null) query['filter[since]'] = since;
    final notices = (await api.getAll('/notices', query: query)).map(Notice.from).toList();

    if (since != null) {
      for (final notice in notices) {
        await Notifications.showMessage('MiTransporte', notice.title, payload: 'notice:${notice.id}');
      }
    }

    final latest = notices.isEmpty ? (since ?? DateTime.now().toUtc().toIso8601String()) : notices.last.createdAt.toUtc().toIso8601String();
    await Storage.setString(_lastNoticeKey, latest);
  }

  /// Avisa de mensajes nuevos en las conversaciones (no en las abiertas en pantalla).
  static Future<void> _syncConversations(ApiClient api) async {
    final seen = await Storage.getJson(_conversationsKey);
    final first = seen.isEmpty;
    final document = await api.get('/conversations', query: {'sort': '-lastMessageAt', 'include': 'topic', 'page[size]': 50});

    for (final conversation in document.resources.map(Conversation.from)) {
      final last = conversation.lastMessageAt;
      if (last == null) continue;
      final previous = seen[conversation.id] == null ? null : DateTime.parse(seen[conversation.id] as String);
      if (!first && (previous == null || last.isAfter(previous))) {
        await Notifications.showMessage('Mensaje nuevo', '${conversation.topicName ?? 'Conversación'} · ${Conversation.recipientLabel(conversation.recipient)}', payload: 'conversation:${conversation.id}');
      }
      seen[conversation.id] = last.toUtc().toIso8601String();
    }

    await Storage.setJson(_conversationsKey, seen);
  }

  /// Marca una conversación como vista hasta ahora (al abrirla).
  static Future<void> markConversationSeen(String id, DateTime at) async {
    final seen = await Storage.getJson(_conversationsKey);
    seen[id] = at.toUtc().toIso8601String();
    await Storage.setJson(_conversationsKey, seen);
  }

  static Future<void> reset() async {
    for (final key in [_tripsKey, _stopsKey, _lastSyncKey, _lastNoticeKey, _conversationsKey]) {
      await Storage.setString(key, null);
    }
  }
}
