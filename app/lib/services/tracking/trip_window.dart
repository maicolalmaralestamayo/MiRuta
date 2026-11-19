import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:miruta_alarm/miruta_alarm.dart';

import '../../core/storage.dart';
import '../app_settings.dart';
import '../notification_texts.dart';
import '../notifications.dart';
import 'trip_permissions.dart';
import 'tracking_service.dart';

/// Un viaje en que viaja la persona (meta.myTrips de GET sync).
class WindowTrip {
  final String id;
  final String itineraryId;
  final String? itineraryName;
  final String direction;
  final String status;
  final DateTime departsAt;
  final DateTime? statusChangedAt;
  final String? myStopId;
  final String? myState;
  final DateTime? myStateAt;

  /// Viaja en él aunque no tenga parada habitual.
  final bool travels;

  const WindowTrip({
    required this.id,
    this.itineraryId = '',
    this.itineraryName,
    this.direction = 'ida',
    this.status = 'planificado',
    required this.departsAt,
    this.statusChangedAt,
    this.myStopId,
    this.myState,
    this.myStateAt,
    this.travels = true,
  });

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory WindowTrip.fromJson(Map<String, dynamic> j) => WindowTrip(
        id: '${j['id']}',
        itineraryId: '${j['itineraryId'] ?? ''}',
        itineraryName: j['itineraryName']?.toString(),
        direction: '${j['direction'] ?? 'ida'}',
        status: '${j['status'] ?? 'planificado'}',
        departsAt: _date(j['departsAt']) ?? DateTime.now(),
        statusChangedAt: _date(j['statusChangedAt']),
        myStopId: j['myStopId']?.toString(),
        myState: j['myState']?.toString(),
        myStateAt: _date(j['myStateAt']),
        travels: j['travels'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'itineraryId': itineraryId,
        'itineraryName': itineraryName,
        'direction': direction,
        'status': status,
        'departsAt': departsAt.toIso8601String(),
        'statusChangedAt': statusChangedAt?.toIso8601String(),
        'myStopId': myStopId,
        'myState': myState,
        'myStateAt': myStateAt?.toIso8601String(),
        'travels': travels,
      };

  bool get outbound => direction == 'ida';

  bool get closed => status == 'terminado' || status == 'cancelado';

  /// «Ruta 1 • Ida».
  String get title => '${itineraryName ?? 'Viaje'} • ${outbound ? 'Ida' : 'Regreso'}';
}

/// Ventana de viaje de un trabajador (docs/11 §11.62): desde X antes de la
/// salida planificada hasta Y después de que el viaje termine para él (su
/// estado definitivo o el fin del viaje). Sin fin conocido, como mucho hasta
/// «Duración máxima» y una hora más después de la salida.
class WindowSlot {
  final WindowTrip trip;
  final DateTime start;
  final DateTime end;

  const WindowSlot(this.trip, this.start, this.end);

  bool contains(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}

/// Planificación de la ventana de viaje: dentro, el servicio de ubicación en
/// primer plano envía y recibe cada «Frecuencia corta» (arrancado por una alarma exacta X antes
/// de la salida, aunque la app esté cerrada); fuera, solo la tarea en segundo
/// plano cada «Frecuencia larga», sin GPS (con la app abierta, cada «Frecuencia corta»).
class TripWindow {
  static const _tripsKey = 'user.window.trips';
  static const _doneKey = 'user.window.done';

  /// Viajes cuya línea abrió quien viaja en ellos: su ventana empieza ya
  /// (docs/11 §11.67: «Ver recorrido» desde Planificado, con datos que se actualizan).
  static const _openedKey = 'user.window.opened';

  /// Próxima conexión con el servidor (contador de la barra superior).
  static final nextContact = ValueNotifier<DateTime?>(null);

  static Future<void> save(List<Map<String, dynamic>> trips) => Storage.setString(_tripsKey, jsonEncode(trips));

  /// Añade (o pone al día) un viaje en que viaja, sin esperar a la próxima
  /// consulta (docs/11 §11.65): al abrir su línea del recorrido. En la 4.3.0
  /// la ventana dependía solo de la lista guardada en la última consulta y,
  /// si el viaje se planificó después, no se abría: ni contador corto ni
  /// cálculo de su estado.
  static Future<void> remember(WindowTrip trip, {bool openNow = false}) async {
    final list = [for (final t in await trips()) if (t.id != trip.id) t.toJson(), trip.toJson()];
    await save(list);
    if (openNow) {
      final json = await Storage.getJson(_openedKey);
      json[trip.id] = DateTime.now().toIso8601String();
      while (json.length > 30) {
        json.remove(json.keys.first);
      }
      await Storage.setJson(_openedKey, json);
    }
  }

  /// Desde cuándo está abierta la línea de cada viaje (ventana adelantada).
  static Future<Map<String, DateTime>> opened() async {
    final json = await Storage.getJson(_openedKey);
    return {for (final e in json.entries) if (DateTime.tryParse('${e.value}') != null) e.key: DateTime.parse('${e.value}')};
  }

  static Future<List<WindowTrip>> trips() async {
    final raw = await Storage.getString(_tripsKey);
    if (raw == null) return const [];
    try {
      return [for (final t in jsonDecode(raw) as List) WindowTrip.fromJson(Map<String, dynamic>.from(t as Map))];
    } catch (_) {
      return const [];
    }
  }

  /// Viajes que ya terminaron para él según su teléfono (estado definitivo).
  static Future<Map<String, DateTime>> done() async {
    final json = await Storage.getJson(_doneKey);
    return {for (final e in json.entries) e.key: DateTime.tryParse('${e.value}') ?? DateTime.now()};
  }

  static Future<void> markDone(String tripId, DateTime at) async {
    final json = await Storage.getJson(_doneKey);
    if (json.containsKey(tripId)) return;
    json[tripId] = at.toIso8601String();
    // Solo los últimos.
    while (json.length > 30) {
      json.remove(json.keys.first);
    }
    await Storage.setJson(_doneKey, json);
  }

  /// Ventanas abiertas o futuras, por orden de inicio (código puro, con pruebas).
  static List<WindowSlot> slots(List<WindowTrip> trips, Map<String, DateTime> done, AppSettings settings, DateTime now, {Map<String, DateTime> opened = const {}}) {
    final result = <WindowSlot>[];
    for (final trip in trips) {
      // Parada habitual opcional (docs/11 §11.65): viaja en todos los viajes de sus itinerarios.
      if (trip.myStopId == null && !trip.travels) continue;
      var start = trip.departsAt.subtract(settings.windowBefore);
      // Abrió su línea antes: la ventana empieza entonces (si el viaje sigue abierto).
      final openedAt = opened[trip.id];
      if (openedAt != null && openedAt.isBefore(start) && !trip.closed) start = openedAt;
      final cap = trip.departsAt.add(settings.duration('duracion_maxima') + const Duration(hours: 1));
      DateTime? ended;
      DateTime? earliest(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isBefore(b) ? a : b);
      if (trip.closed) ended = trip.statusChangedAt ?? trip.departsAt;
      ended = earliest(ended, done[trip.id]);
      // Estado final (Dejado o No viajaré, docs/11 §11.67): termina Y después.
      if (const {'dejado', 'no_viajare'}.contains(trip.myState)) ended = earliest(ended, trip.myStateAt ?? now);
      var end = ended == null ? cap : ended.add(settings.windowAfter);
      if (end.isAfter(cap)) end = cap;
      if (end.isAfter(now) && end.isAfter(start)) result.add(WindowSlot(trip, start, end));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static Future<List<WindowSlot>> current({AppSettings? settings}) async =>
      slots(await trips(), await done(), settings ?? await AppSettings.cached(), DateTime.now(), opened: await opened());

  /// La ventana abierta ahora (o null).
  static Future<WindowSlot?> open({AppSettings? settings}) async {
    final now = DateTime.now();
    return (await current(settings: settings)).where((s) => s.contains(now)).firstOrNull;
  }

  /// Programa la ventana: si está abierta y el servicio no corre, lo arranca
  /// (con la app a la vista) o pide a la alarma que lo arranque en un momento;
  /// si no, programa la alarma exacta para la próxima. Con el GPS apagado el
  /// servicio arranca igual y su notificación «Mi estado» pide activarlo
  /// (docs/11 §11.63). Sin permiso de ubicación no puede arrancar: «Mi estado»
  /// sale como notificación normal al abrirse la ventana.
  static Future<void> reschedule(AppSettings settings, {bool foreground = false}) async {
    try {
      final now = DateTime.now();
      final list = slots(await trips(), await done(), settings, now, opened: await opened());
      final active = list.where((s) => s.contains(now)).firstOrNull;
      final upcoming = list.where((s) => s.start.isAfter(now)).firstOrNull;
      final permissions = await TripPermissions.check();
      if (!permissions.granted) {
        await MirutaAlarm.cancel();
        final slot = active ?? upcoming;
        if (slot == null) {
          await Notifications.cancelMyStateFallback();
        } else {
          final content = myStateNotice(stateName: '', gpsOn: permissions.locationOn, alwaysPermission: false);
          await Notifications.showMyStateFallback(content, payload: permissions.locationOn ? 'permiso' : 'gps', at: active != null ? null : slot.start);
        }
        return;
      }
      await Notifications.cancelMyStateFallback();
      if (active != null && !await TrackingService.isRunning) {
        if (foreground) {
          await TrackingService.startWindow(active, settings);
        } else {
          await MirutaAlarm.schedule(now.add(const Duration(seconds: 3)), TrackingService.alarmPayload(active.trip.title, settings.shortEvery));
          return;
        }
      }
      if (upcoming != null) {
        await MirutaAlarm.schedule(upcoming.start, TrackingService.alarmPayload(upcoming.trip.title, settings.shortEvery));
      } else {
        await MirutaAlarm.cancel();
      }
    } catch (_) {
      // Fuera de Android (pruebas) o sin servicios del sistema.
    }
  }
}
