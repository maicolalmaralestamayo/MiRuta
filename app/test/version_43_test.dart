import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/notification_texts.dart';
import 'package:mitransporte/services/notifications.dart';
import 'package:mitransporte/services/theme_controller.dart';
import 'package:mitransporte/services/tracking/worker_tracker.dart';
import 'package:mitransporte/ui/widgets/app_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Versión 4.3.0 (docs/11 §11.63): textos de las notificaciones, Viajando
/// unificado, selector de tema en un botón y cuenta atrás sin sesión.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Fecha de las notificaciones', () {
    test('día de la semana abreviado y en mayúscula, dd/MM/yy HH:mm', () {
      expect(noticeDate(DateTime(2026, 11, 16, 7, 0)), 'Lun. 16/11/26 07:00');
      expect(noticeDate(DateTime(2026, 11, 18, 9, 5)), 'Mié. 18/11/26 09:05');
      expect(noticeDate(DateTime(2026, 11, 21, 18, 30)), 'Sáb. 21/11/26 18:30');
      expect(noticeDate(DateTime(2026, 11, 22, 0, 0)), 'Dom. 22/11/26 00:00');
    });
  });

  group('Viajes', () {
    final departs = DateTime(2026, 11, 16, 7, 0);

    test('planificado: itinerario, fecha y parada de salida con el tipo de vehículo', () {
      final n = tripNotice(
          status: 'planificado', itineraryName: 'XX Aniversario', direction: 'ida', departsAt: departs, departureStop: 'La llama', vehicleType: 'Microbús');
      expect(n.title, 'Viaje planificado');
      expect(n.lines, ['XX Aniversario • ida', 'Lun. 16/11/26 07:00', 'La llama • Microbús']);
      expect(n.highlight, isNull);
    });

    test('cambiado: una sola línea destacada con lo que cambió', () {
      NoticeContent changed(List<String> c) => tripNotice(status: 'cambiado', itineraryName: 'R', direction: 'regreso', departsAt: departs, changes: c);
      expect(changed(['hora']).title, 'Viaje cambiado');
      expect(changed(['hora']).lines.first, 'R • regreso');
      expect(changed(['hora']).highlight, 'Cambió la hora');
      expect(changed(['hora', 'fecha']).highlight, 'Cambió la fecha y hora');
      expect(changed(['tipo_vehiculo', 'hora', 'fecha']).highlight, 'Cambió la fecha, hora y tipo de vehículo');
      expect(changed(['observacion']).highlight, 'Cambió la observación');
      expect(changed(['parada_salida']).highlight, 'Cambió la parada de salida');
      expect(changed(['tipo_vehiculo']).highlight, 'Cambió el tipo de vehículo');
      expect(changed(const []).highlight, isNull);
    });

    test('la línea de cambios desaparece en cuanto el viaje pasa a otro estado', () {
      final n = tripNotice(status: 'en_ejecucion', itineraryName: 'R', departsAt: departs, changes: const ['hora']);
      expect(n.title, 'Viaje en ejecución');
      expect(n.highlight, isNull);
      expect(tripNotice(status: 'cancelado').title, 'Viaje cancelado');
      expect(tripNotice(status: 'eliminado').title, 'Viaje eliminado');
    });

    test('estado de la notificación según la del servidor', () {
      expect(Notifications.tripNoticeStatusOf('viaje_creado', const {}), 'planificado');
      expect(Notifications.tripNoticeStatusOf('viaje_modificado', const {}), 'cambiado');
      expect(Notifications.tripNoticeStatusOf('viaje_estado', const {'status': 'en_ejecucion'}), 'en_ejecucion');
      expect(Notifications.tripNoticeStatusOf('viaje_eliminado', const {}), 'eliminado');
      expect(Notifications.tripNoticeStatusOf('vehiculo_en_parada', const {}), isNull);
    });

    test('ids estables por viaje', () {
      expect(Notifications.tripId('15'), Notifications.tripId('15'));
      expect(Notifications.tripId('15'), isNot(Notifications.vehicleId('15')));
    });
  });

  group('Vehículo', () {
    const stops = ['Parqueo', 'Coppelia', 'La llama', 'Fábrica'];
    VehicleView view({String? state = 'en_movimiento', int next = 2, bool atStop = false, bool moved = true, bool outbound = true, int sensors = 3}) => VehicleView(
        vehicleType: 'Microbús',
        itineraryName: 'XX Aniversario',
        outbound: outbound,
        state: state,
        sensors: sensors,
        stops: stops,
        nextStopIndex: next,
        atStop: atStop,
        movedOnce: moved);

    test('entre paradas: Anterior y Próxima', () {
      final n = vehicleNotice(view());
      expect(n.title, 'Microbús • en movimiento');
      expect(n.lines, ['XX Aniversario • ida', 'Anterior: Coppelia', 'Próxima: La llama']);
      expect(n.highlight, isNull);
      expect(vehicleNotice(view(state: 'detenido')).title, 'Microbús • detenido');
    });

    test('en la primera parada: solo Próxima y «Primera parada»', () {
      final n = vehicleNotice(view(state: 'detenido', next: 1, moved: false));
      expect(n.lines, ['XX Aniversario • ida', 'Próxima: Coppelia']);
      expect(n.highlight, 'Primera parada');
    });

    test('en la última parada: solo Anterior y «Última parada»', () {
      final n = vehicleNotice(view(state: 'detenido', next: 3, atStop: true));
      expect(n.lines, ['XX Aniversario • ida', 'Anterior: La llama']);
      expect(n.highlight, 'Última parada');
    });

    test('detenido en una parada: Dejando (ida) o Recogiendo (regreso)', () {
      final ida = vehicleNotice(view(state: 'detenido', next: 2, atStop: true));
      expect(ida.lines, ['XX Aniversario • ida', 'Próxima: Fábrica']);
      expect(ida.highlight, 'Dejando en La llama');
      final regreso = vehicleNotice(view(state: 'detenido', next: 1, atStop: true, outbound: false));
      expect(regreso.lines, ['XX Aniversario • regreso', 'Próxima: La llama']);
      expect(regreso.highlight, 'Recogiendo en Coppelia');
    });

    test('sin sensores: solo el tipo de vehículo, últimos datos y «Sin datos»', () {
      final n = vehicleNotice(view(sensors: 0), lastLines: const ['Anterior: Coppelia', 'Próxima: La llama']);
      expect(n.title, 'Microbús');
      expect(n.lines, ['XX Aniversario • ida', 'Anterior: Coppelia', 'Próxima: La llama']);
      expect(n.highlight, 'Sin datos');
      expect(vehicleNotice(view(state: null)).highlight, 'Sin datos');
    });

    test('se quita al llegar a un estado definitivo', () {
      // Desde la 4.4.0 los finales son los mismos en los dos sentidos (docs/11 §11.65).
      for (final s in ['dejado', 'no_recogido', 'retrasado', 'no_voy', 'botado', 'dormido']) {
        expect(WorkerState.isFinalFor(s, outbound: true), isTrue, reason: s);
        expect(WorkerState.isFinalFor(s, outbound: false), isTrue, reason: s);
      }
      expect(WorkerState.isFinalFor('viajando', outbound: true), isFalse);
      expect(WorkerState.isFinalFor('viajando', outbound: false), isFalse);
      expect(WorkerState.isFinalFor('en_parada', outbound: false), isFalse);
    });
  });

  group('Mi estado', () {
    test('estado, itinerario y mi parada', () {
      final n = myStateNotice(stateName: WorkerState.notice('en_parada'), state: 'en_parada', itineraryName: 'XX Aniversario', myStop: 'La llama');
      expect(n.title, 'En la parada');
      expect(n.lines, ['XX Aniversario • ida', 'Mi parada: La llama']);
      expect(n.highlight, isNull);
    });

    test('destacadas: Retrasado, No recogido y estado definitivo', () {
      expect(myStateNotice(stateName: 'Retrasado', state: 'retrasado').highlight, 'Llegó tarde a la parada');
      expect(myStateNotice(stateName: 'No recogido', state: 'no_recogido', outbound: false).highlight, 'El vehículo pasó sin recogerle');
      expect(myStateNotice(stateName: 'Dejado', state: 'dejado', ended: true).highlight, 'Ya puede quitar la ubicación');
    });

    test('sin GPS ni permiso: solo el aviso (primero el GPS)', () {
      final gps = myStateNotice(stateName: 'Viajando', state: 'viajando', itineraryName: 'R', gpsOn: false, alwaysPermission: false);
      expect(gps.title, 'Active la ubicación (GPS)');
      expect(gps.allLines, isEmpty);
      final permission = myStateNotice(stateName: 'Viajando', state: 'viajando', itineraryName: 'R', alwaysPermission: false);
      expect(permission.title, 'Permita la ubicación todo el tiempo');
      expect(permission.allLines, isEmpty);
    });

    test('nombres de los estados', () {
      expect(WorkerState.notice('de_camino'), 'De camino');
      expect(WorkerState.notice('no_voy'), 'No voy');
      expect(WorkerState.notice('recogido'), 'Viajando');
      expect(WorkerState.name('recogido'), 'Viajando');
    });
  });

  group('Solicitudes, mensajes y actualizaciones', () {
    test('pendientes: una sola, sin tipos a cero', () {
      expect(pendingApplicationsNotice(), isNull);
      final one = pendingApplicationsNotice(itinerary: 1)!;
      expect(one.title, '1 solicitud pendiente');
      expect(one.lines, ['Itinerario: 1']);
      final admin = pendingApplicationsNotice(entity: 1, itinerary: 2, accessRecovery: 1)!;
      expect(admin.title, '4 solicitudes pendientes');
      expect(admin.lines, ['Entidad: 1 • Itinerario: 2 • Olvidé algo: 1']);
      expect(pendingApplicationsNotice(entity: 1, itinerary: 2)!.lines, ['Entidad: 1 • Itinerario: 2']);
    });

    test('respuesta a una solicitud propia', () {
      final at = DateTime(2026, 11, 16, 8, 40);
      final entity = resolvedApplicationNotice(approved: true, type: 'entidad', entity: 'ESM', resolvedAt: at);
      expect(entity.title, 'Solicitud aprobada');
      expect(entity.lines, ['Entidad: ESM', 'Lun. 16/11/26 08:40']);
      expect(entity.highlight, isNull);
      final itinerary = resolvedApplicationNotice(
          approved: false, type: 'itinerario', entity: 'ESM', itinerary: 'XX Aniversario', stop: 'La llama', resolvedAt: at, reason: 'Sin plaza');
      expect(itinerary.title, 'Solicitud rechazada');
      expect(itinerary.lines, ['Itinerario: XX Aniversario • ESM', 'Parada: La llama', 'Lun. 16/11/26 08:40']);
      expect(itinerary.highlight, 'Motivo: Sin plaza');
    });

    test('respuesta del desarrollador', () {
      final at = DateTime(2026, 11, 16, 9, 25);
      final one = developerReplyNotice(text: 'Ya está arreglado', sentAt: at);
      expect(one.title, 'Respuesta del desarrollador');
      expect(one.lines, ['Ya está arreglado', 'Lun. 16/11/26 09:25']);
      expect(one.highlight, isNull);
      expect(developerReplyNotice(text: 'x', sentAt: at, unread: 3).highlight, '3 mensajes sin leer');
    });

    test('actualización disponible u obligatoria', () {
      final available = updateNotice(versionName: '4.3.0', size: '13.6 MB');
      expect(available.title, 'Actualización disponible');
      expect(available.lines, ['Versión 4.3.0', 'Tamaño: 13.6 MB']);
      expect(available.highlight, isNull);
      expect(updateNotice(versionName: '4.3.0', mandatory: true).title, 'Actualización obligatoria');
      expect(updateNotice(versionName: '4.3.0', mandatory: true).highlight, 'Instálela para seguir usando MiRuta');
    });

    test('la destacada va en naranja en el formato HTML de Android', () {
      final html = noticeHtml(const NoticeContent('T', ['a < b', 'c'], 'Sin datos'));
      expect(html, 'a &lt; b<br>c<br><font color="$highlightColor"><b>Sin datos</b></font>');
    });
  });

  group('Viajando unificado', () {
    const route = [
      RouteStop('1', 'A', GeoPoint(23.0, -82.0)),
      RouteStop('2', 'B', GeoPoint(23.01, -82.0)),
    ];

    test('«recogido» de la 4.2.0 es Viajando y hace de sensor', () {
      final tracker = WorkerTracker(outbound: false, route: route)..declare('recogido');
      expect(tracker.state, 'viajando');
      expect(tracker.isSensor, isTrue);
      final restored = WorkerTracker.fromJson({...tracker.toJson(), 'state': 'recogido'});
      expect(restored.state, 'viajando');
    });
  });

  testWidgets('tema en un solo botón: icono del modo actual y menú', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: ThemeModeSelector()))));
    expect(find.byIcon(Icons.settings_suggest_outlined), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
    await tester.tap(find.byType(ThemeModeSelector));
    await tester.pumpAndSettle();
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Oscuro'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    await tester.tap(find.text('Claro'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ThemeController.mode.value, ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    await ThemeController.set(ThemeMode.system);
  });

  testWidgets('cuenta atrás sin sesión', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CountdownLabel(next: DateTime.now().add(const Duration(seconds: 30))))));
    expect(find.textContaining(' s'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CountdownLabel(next: null))));
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
