import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/models.dart';
import 'app_updates.dart';
import 'notifications.dart';
import 'qr/qr_store.dart';
import 'templates.dart';
import 'user_settings.dart';

/// Partes de la sincronización. Cada una tiene su frecuencia en segundo plano.
enum SyncPart {
  trips('trips_poll_background_minutes'),
  notices('notices_poll_background_minutes'),
  conversations('conversations_poll_background_minutes'),
  tripChats('trip_chat_poll_background_minutes'),

  /// Comprobar si hay versión nueva de la app (docs/09 §33); el ajuste va en horas.
  updates('update_check_hours', hours: true);

  final String setting;
  final bool hours;

  const SyncPart(this.setting, {this.hours = false});

  String get task => 'sync-$name';

  static SyncPart? fromTask(String task) => values.where((part) => part.task == task).firstOrNull;
}

/// Sincronización de viajes, avisos y mensajes, con detección de cambios
/// (docs/07-algoritmos.md §7.15). Se usa con la app abierta y en segundo plano.
class SyncService {
  static const _tripsKey = 'user.trips';
  static const _stopsKey = 'user.stops';
  static const _lastSyncKey = 'user.last_sync';
  static const _lastNoticeKey = 'user.last_notice';
  static const _conversationsKey = 'user.conversations_seen';
  static const _tripChatsKey = 'user.trip_chats_seen';
  static const meKey = 'user.me';

  /// El chofer (`driver`) es una pertenencia (`workers`) con los nombres de la persona.
  static const tripInclude = 'itinerary,vehicle.vehicleType,driver';

  /// Guarda los datos del usuario que necesitan las tareas en segundo plano.
  static Future<void> rememberMe(Me me) => Storage.setJson(meKey, {
        'id': me.id,
        'userId': me.userId,
        'isAdmin': me.isAdmin,
        'workerIds': me.workerIds.toList(),
        'itineraryIds': me.itineraryIds.toList(),
        'itineraryEntities': {for (final m in me.memberships) if (m.itineraryId != null) m.itineraryId!: m.entityId},
        'permissions': me.permissions.toJson(),
      });

  static Permissions _permissions(Map<String, dynamic> me) => Permissions.fromJson(me['permissions'] as List?,
      isAdmin: me['isAdmin'] == true, itineraryEntities: Map<String, String>.from(me['itineraryEntities'] as Map? ?? const {}));

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

  /// Sincroniza las partes indicadas (todas si no se indica ninguna). En
  /// segundo plano cada parte tiene su propia tarea con su frecuencia.
  static Future<void> run(ApiClient api, {Set<SyncPart> parts = const {...SyncPart.values}, bool notifyChanges = true}) async {
    final me = await cachedMe();
    if (me['id'] == null) return;

    if (parts.contains(SyncPart.trips)) {
      // QR: clave del servidor, listas para escanear sin conexión y envío de la cola.
      await QrSync.run(api, me);
      final settings = await UserSettings.refresh(api).catchError((_) => UserSettings.cached());
      for (final itineraryId in (me['itineraryIds'] as List? ?? const [])) {
        await _syncStops(api, '$itineraryId');
      }
      await _syncTrips(api, me, settings, notifyChanges);
    }
    if (parts.contains(SyncPart.notices)) await _syncNotices(api);
    if (parts.contains(SyncPart.updates)) await _notifyUpdate(api);
    final settings = await UserSettings.cached();
    // Avisos de mensajes nuevos, si el usuario los tiene activados (docs/09 §36).
    if (parts.contains(SyncPart.conversations)) await _syncConversations(api, settings.boolean('conversation_notice_enabled', true));
    if (parts.contains(SyncPart.tripChats)) await _syncTripChats(api, (me['userId'] ?? '') as String, settings.boolean('trip_chat_notice_enabled', true));
  }

  static Future<void> _syncStops(ApiClient api, String itineraryId) async {
    final stops = await api.getAll('/stops', query: {'filter[itinerary]': itineraryId});
    final cached = await Storage.getJson(_stopsKey);
    await Storage.setJson(_stopsKey, {...cached, for (final r in stops) r.id: Stop.from(r).toJson()});
  }

  /// De su itinerario (en cualquiera de sus Entidades) o lo conduce.
  static bool _isMine(Trip trip, Map<String, dynamic> me) =>
      ((me['itineraryIds'] as List?) ?? const []).contains(trip.itineraryId) || ((me['workerIds'] as List?) ?? const []).contains(trip.driverId);

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
    final levels = await Storage.getJson(_levelsKey);
    String? newest = lastSync;

    for (final resource in resources) {
      final trip = Trip.from(resource);
      if (trip.updatedAt != null) newest = trip.updatedAt!.toUtc().toIso8601String();
      await _checkSaturation(trip, me, settings, levels, notifyChanges);
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
    // Solo se recuerdan los viajes que siguen en el teléfono o acaban de llegar.
    if (levels.length > 1000) levels.removeWhere((id, _) => !cache.containsKey(id) && !resources.any((r) => r.id == id));
    await Storage.setJson(_levelsKey, levels);
    if (newest != null) await Storage.setString(_lastSyncKey, newest);
  }

  static const _levelsKey = 'sync.occupancy_levels';

  /// Avisos de saturación (docs/08-version-2.md §8.9), según los ajustes del
  /// usuario: nivel, de qué viajes y cuándo (al cambiar, antes de la salida o los dos).
  static Future<void> _checkSaturation(Trip trip, Map<String, dynamic> me, UserSettings settings, Map<String, dynamic> levels, bool notifyChanges) async {
    final previous = levels[trip.id] as String?;
    levels[trip.id] = trip.occupancyLevel;

    final pending = trip.status == TripStatus.confirmed || trip.status == TripStatus.unconfirmed;
    final managed = _permissions(me).can(Op.tripsEdit, entityId: trip.entityId, itineraryId: trip.itineraryId);
    final inScope = _isMine(trip, me) || (settings.string('saturation_notice_scope', 'managed') == 'managed' && managed);
    final wanted = settings.boolean('saturation_notice_enabled', true) && pending && inScope && trip.departsAt.isAfter(DateTime.now());
    final qualifies = settings.string('saturation_notice_level', 'overloaded') == 'saturated' ? trip.occupancyLevel != 'normal' : trip.overloaded;
    final when = settings.string('saturation_notice_when', 'change');

    if (wanted && qualifies && notifyChanges && previous != null && previous != trip.occupancyLevel && when != 'before') {
      await Notifications.showSaturation(trip);
    }

    if (wanted && qualifies && when != 'change') {
      final at = trip.departsAt.subtract(Duration(minutes: settings.integer('saturation_notice_minutes_before', 120)));
      if (at.isAfter(DateTime.now())) await Notifications.scheduleSaturation(trip, at);
    } else {
      await Notifications.cancelSaturation(trip);
    }
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
    // Ausencias sin aprobación (docs/11 §11.12); las indefinidas, hasta dentro de un año.
    final resources = await api.getAll('/absences', query: {'filter[mine]': 'true'});
    return resources.map(Absence.from).map((a) => (a.start, (a.end ?? DateTime.now().add(const Duration(days: 365))).add(const Duration(days: 1)))).toList();
  }

  static Future<void> _syncNotices(ApiClient api) async {
    final since = await Storage.getString(_lastNoticeKey);
    final query = <String, dynamic>{'filter[unread]': 'true', 'sort': 'createdAt'};
    if (since != null) query['filter[since]'] = since;
    final notices = (await api.getAll('/notices', query: query)).map(Notice.from).toList();

    if (since != null) {
      for (final notice in notices) {
        await Notifications.showMessage(notice.title, notice.text, payload: 'notice:${notice.id}');
      }
    }

    final latest = notices.isEmpty ? (since ?? DateTime.now().toUtc().toIso8601String()) : notices.last.createdAt.toUtc().toIso8601String();
    await Storage.setString(_lastNoticeKey, latest);
  }

  /// Avisa de mensajes nuevos en las conversaciones (no en las abiertas en pantalla).
  static Future<void> _syncConversations(ApiClient api, bool notify) async {
    final seen = await Storage.getJson(_conversationsKey);
    final first = seen.isEmpty;
    final document = await api.get('/conversations', query: {'sort': '-lastMessageAt', 'include': 'topic', 'page[size]': 50});

    for (final conversation in document.resources.map(Conversation.from)) {
      final last = conversation.lastMessageAt;
      if (last == null) continue;
      final previous = seen[conversation.id] == null ? null : DateTime.parse(seen[conversation.id] as String);
      if (notify && !first && (previous == null || last.isAfter(previous))) {
        await Notifications.showMessage('Mensaje nuevo', '${conversation.topicName ?? 'Conversación'} · ${conversation.recipientLabel}', payload: 'conversation:${conversation.id}');
      }
      seen[conversation.id] = last.toUtc().toIso8601String();
    }

    await Storage.setJson(_conversationsKey, seen);
  }

  /// Avisa una vez de cada versión nueva de la app.
  static Future<void> _notifyUpdate(ApiClient api) async {
    final update = await AppUpdates.check(api);
    if (update != null && await AppUpdates.shouldNotify(update)) {
      await Notifications.showMessage(
        'Actualización de MiRuta',
        'Hay una versión nueva (${update.versionName})${update.mandatory ? ', obligatoria' : ''}. Abra la app para instalarla.',
      );
    }
  }

  /// Avisa de mensajes nuevos de otros en el chat de los viajes confirmados en curso o próximos.
  static Future<void> _syncTripChats(ApiClient api, String meId, bool notify) async {
    final seen = await Storage.getJson(_tripChatsKey);
    final now = DateTime.now();
    final trips = (await cachedTrips()).where((t) => t.isConfirmed && t.returnsAt.isAfter(now) && t.departsAt.isBefore(now.add(const Duration(days: 1))));

    for (final trip in trips) {
      final since = seen[trip.id] as String?;
      final messages = (await api.getAll('/trips/${trip.id}/messages', query: {'include': 'author', 'filter[since]': ?since})).map(Message.from).toList();
      if (messages.isEmpty) continue;
      if (notify && since != null) {
        for (final message in messages.where((m) => m.authorId != meId)) {
          await Notifications.showMessage('${message.authorName ?? 'Mensaje'} · ${trip.itineraryName ?? 'Viaje'}', message.body, payload: 'trip:${trip.id}');
        }
      }
      seen[trip.id] = messages.last.createdAt.toUtc().toIso8601String();
    }

    await Storage.setJson(_tripChatsKey, seen);
  }

  static Future<void> markTripChatSeen(String tripId, DateTime at) async {
    final seen = await Storage.getJson(_tripChatsKey);
    seen[tripId] = at.toUtc().toIso8601String();
    await Storage.setJson(_tripChatsKey, seen);
  }

  /// Marca una conversación como vista hasta ahora (al abrirla).
  static Future<void> markConversationSeen(String id, DateTime at) async {
    final seen = await Storage.getJson(_conversationsKey);
    seen[id] = at.toUtc().toIso8601String();
    await Storage.setJson(_conversationsKey, seen);
  }

  static Future<void> reset() async {
    for (final key in [_tripsKey, _stopsKey, _lastSyncKey, _lastNoticeKey, _conversationsKey, _tripChatsKey]) {
      await Storage.setString(key, null);
    }
  }
}
