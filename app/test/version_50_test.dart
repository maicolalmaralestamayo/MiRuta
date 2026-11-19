import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/formats.dart';
import 'package:mitransporte/core/server_clock.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/services/app_settings.dart';
import 'package:mitransporte/services/tracking/tracking_service.dart';
import 'package:mitransporte/services/tracking/trip_window.dart';
import 'package:mitransporte/ui/trips/trip_card.dart';
import 'package:mitransporte/ui/trips/trip_form_screen.dart';
import 'package:mitransporte/ui/trips/trip_line_screen.dart';
import 'package:mitransporte/ui/widgets/app_scaffold.dart';
import 'package:mitransporte/ui/widgets/busy.dart';

/// Versión 5.0.0 (docs/11 §11.67). La máquina de estados del trabajador está
/// en worker_tracker_test.dart.
void main() {
  tearDown(() => ServerClock.set());

  Trip trip({String status = 'planificado', List<String> changes = const [], bool simulation = false}) => Trip(
        id: '1',
        direction: 'ida',
        date: DateTime(2026, 11, 19),
        departureTime: '10:30',
        departsAt: DateTime(2026, 11, 19, 10, 30),
        status: status,
        changes: changes,
        itineraryId: '4',
        itineraryName: 'XX Aniversario',
        vehicleTypeName: 'Carro Dongfeng',
        simulation: simulation,
      );

  group('Tarjeta del viaje con el formato de la notificación', () {
    test('«Viaje [estado]»; itinerario, sentido, fecha y hora de 24 h; parada de salida y tipo de vehículo', () {
      final t = TripCardText.of(trip(), departure: 'Parqueo B');
      expect(t.title, 'Viaje planificado');
      expect(t.route, 'XX Aniversario • ida • Jue. 19/11/26 10:30');
      expect(t.details, 'Parqueo B • Carro Dongfeng');
      expect(t.highlight, isNull);
      expect(TripCardText.of(trip(status: 'en_ejecucion')).title, 'Viaje en ejecución');
      expect(TripCardText.of(trip(status: 'terminado')).title, 'Viaje terminado');
      expect(TripCardText.of(trip(status: 'cancelado')).title, 'Viaje cancelado');
      expect(TripCardText.of(trip(simulation: true)).route, startsWith('Simulación • XX Aniversario'));
    });

    test('cambiado: línea naranja con lo que cambió, solo mientras sigue Planificado', () {
      final t = TripCardText.of(trip(changes: ['fecha', 'hora']), departure: 'Parqueo B');
      expect(t.title, 'Viaje cambiado');
      expect(t.highlight, 'Cambió la fecha y hora');
      expect(TripCardText.of(trip(status: 'en_ejecucion', changes: ['hora'])).highlight, isNull);
    });

    test('cancelar solo un Planificado; eliminar solo un Cancelado o Terminado', () {
      expect(trip().canCancel, isTrue);
      expect(trip().canDelete, isFalse);
      expect(trip(status: 'en_ejecucion').canCancel, isFalse);
      expect(trip(status: 'en_ejecucion').canDelete, isFalse);
      expect(trip(status: 'cancelado').canDelete, isTrue);
      expect(trip(status: 'terminado').canDelete, isTrue);
      expect(tripStatusVerb('cancelado'), ('Cancelar', 'Cancelando'));
      expect(tripStatusVerb('en_ejecucion'), ('Iniciar', 'Iniciando'));
    });
  });

  group('Horas en la zona del servidor (captura 02 de la 4.5.0)', () {
    test('la zona sale de las fechas del servidor', () {
      expect(ServerClock.offsetOf('2026-11-19T12:05:00-05:00'), const Duration(hours: -5));
      expect(ServerClock.offsetOf('2026-11-19T17:05:00Z'), Duration.zero);
      expect(ServerClock.offsetOf('2026-11-19'), isNull);
    });

    test('con el teléfono en otra zona se muestra la hora del servidor, no la del teléfono', () async {
      // Una zona con una hora de diferencia con la del teléfono (como un teléfono con la zona mal puesta).
      final phone = DateTime.now().timeZoneOffset;
      ServerClock.set(offset: phone - const Duration(hours: 1));
      final instant = DateTime.parse('2026-11-19T17:05:00Z');
      final wall = instant.toUtc().add(phone - const Duration(hours: 1));
      expect(formatTime(instant), '${wall.hour.toString().padLeft(2, '0')}:05');
      // Y la salida (statusChangedAt/startedAt) y el paso por la primera parada se ven iguales.
      expect(formatTime(DateTime.parse('2026-11-19T12:05:00-05:00')), formatTime(instant));
    });

    test('la hora de captura va en UTC, corregida con el reloj del servidor', () {
      ServerClock.set(skew: const Duration(minutes: 2));
      final at = DateTime.utc(2026, 11, 19, 15, 0);
      expect(ServerClock.stamp(at), '2026-11-19T15:02:00.000Z');
    });
  });

  group('Ver recorrido', () {
    LiveStop stop(int i, {String state = 'en_espera', bool left = false, Map<String, int> counts = const {}}) =>
        LiveStop(index: i, stopId: '${i + 1}', landmark: ['Parqueo', 'ITM', 'Banco', 'La llama'][i], state: state, left: left, passed: state != 'en_espera', counts: counts);

    test('cantidades por estado: sin ceros ni Viajando; en la ida sin Dejados y en el regreso sin En Parada', () {
      final counts = {'en_parada': 2, 'acercandose': 1, 'viajando': 5, 'dejado': 3, 'no_recogido': 0, 'llegada_tarde': 1};
      expect([for (final c in stopCountChips(counts, outbound: true)) c.$1], ['Acercándose: 1', 'En Parada: 2', 'Llegada tarde: 1']);
      expect([for (final c in stopCountChips(counts, outbound: false)) c.$1], ['Acercándose: 1', 'Llegada tarde: 1', 'Dejados: 3']);
    });

    test('el vehículo en medio del tramo entre la última parada que dejó y la siguiente, o sobre la parada si está detenido en ella', () {
      final stops = [stop(0, state: 'recogida', left: true), stop(1, state: 'volada', left: true), stop(2), stop(3)];
      expect(vehiclePosition(TripLive(tripId: '1', status: 'en_ejecucion', stops: stops, nextStopIndex: 2, vehicleState: 'en_movimiento')), (1, false));
      final stoppedAt = [stop(0, state: 'recogida', left: true), stop(1, state: 'volada', left: true), stop(2, state: 'recogida'), stop(3)];
      expect(vehiclePosition(TripLive(tripId: '1', status: 'en_ejecucion', stops: stoppedAt, nextStopIndex: 2, vehicleState: 'detenido', vehicleAtStop: true)), (2, true));
      expect(vehiclePosition(TripLive(tripId: '1', status: 'planificado', stops: stops)), isNull);
    });

    test('tarjeta de estado: estado; parada • movimiento • velocidad; coordenadas • fecha y hora', () {
      final live = TripLive(tripId: '1', stops: [stop(0), stop(1)], myState: 'acercandose', myStopId: '2');
      final motion = MyMotion(state: 'acercandose', stopName: 'ITM', moving: true, speedKmh: 4.2, latitude: 23.073451, longitude: -82.430749, at: DateTime(2026, 11, 19, 10, 31));
      final lines = myStateLines(live, motion);
      expect(lines[0], 'Acercándose a Parada');
      expect(lines[1], 'ITM • En movimiento • 4 km/h');
      expect(lines[2], '23.07345, -82.43075 • Jue. 19/11/26 10:31');
      expect(lines.join(), isNot(contains('·')), reason: 'el separador es siempre «•»');
      // Viajando: sin parada; movimiento y velocidad del vehículo.
      final travelling = TripLive(tripId: '1', status: 'en_ejecucion', stops: [stop(0)], myState: 'viajando', vehicleState: 'detenido', vehicleSpeed: 0);
      expect(myStateLines(travelling, const MyMotion(state: 'viajando', moving: true, speedKmh: 30))[1], 'Detenido • 0 km/h');
      // Dejado: la parada donde se le dejó.
      expect(myStateLines(TripLive(tripId: '1', stops: [stop(0)], myState: 'dejado', myStopName: 'La llama'), null)[1], startsWith('La llama'));
      expect(myStateLines(TripLive(tripId: '1', stops: [stop(0)]), null)[2], 'Sin ubicación todavía');
    });

    test('estados de las paradas', () {
      expect(StopState.name('en_espera'), 'En espera');
      expect(StopState.name('recogida'), 'Recogida');
      expect(StopState.name('volada'), 'Volada');
      expect(StopState.name('omitida'), 'Omitida');
    });

    test('al abrir su línea, la ventana de viaje empieza ya (Ver recorrido desde Planificado)', () {
      const settings = AppSettings({'anticipacion_viaje': '10min'});
      final departs = DateTime(2026, 11, 19, 10, 30);
      final w = WindowTrip(id: '9', departsAt: departs, myStopId: '1');
      final now = DateTime(2026, 11, 19, 8, 0);
      expect(TripWindow.slots([w], const {}, settings, now).single.contains(now), isFalse);
      final opened = TripWindow.slots([w], const {}, settings, now, opened: {'9': DateTime(2026, 11, 19, 7, 59)});
      expect(opened.single.contains(now), isTrue);
      // Al dejar de verla, la ventana vuelve a empezar X antes de la salida.
      final old = TripWindow.slots([w], const {}, settings, now, opened: {'9': now.subtract(TripWindow.openedFor + const Duration(minutes: 1))});
      expect(old.single.contains(now), isFalse);
    });
  });

  group('Interfaz', () {
    test('nombres propios de las acciones y sus spinners', () {
      expect(progressiveLabel('Aprobar Solicitud'), 'Aprobando Solicitud');
      expect(progressiveLabel('Rechazar Solicitud'), 'Rechazando Solicitud');
      expect(progressiveLabel('Solicitar Entidad'), 'Solicitando Entidad');
      expect(progressiveLabel('Cancelar Viaje'), 'Cancelando Viaje');
      expect(progressiveLabel('Iniciar Viaje'), 'Iniciando Viaje');
      expect(progressiveLabel('Marcar paso por parada'), 'Marcando paso por parada');
      expect(progressiveLabel('Crear Parada'), 'Creando Parada');
    });

    testWidgets('la cuenta atrás en cero: el icono gira en lugar del «0»', (tester) async {
      final now = DateTime.now();
      expect(countdownDue(now.subtract(const Duration(seconds: 1))), isTrue);
      expect(countdownDue(now.add(const Duration(seconds: 5))), isFalse);
      expect(countdownDue(null), isFalse);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CountdownLabel(next: now.subtract(const Duration(seconds: 3))))));
      expect(find.text('0 s'), findsNothing);
      expect(find.byType(RotationTransition), findsWidgets);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('selector de hora: digital, 24 h, dos campos (hora y minutos), sin reloj ni a. m./p. m.', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async => picked = await pickTime24(context, const TimeOfDay(hour: 17, minute: 0)), child: const Text('abrir')))),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('17'), findsOneWidget);
      expect(find.text('00'), findsOneWidget);
      expect(find.textContaining('a. m.'), findsNothing);
      expect(find.textContaining('p. m.'), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '24');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(picked, isNull, reason: 'la hora va de 00 a 23');
      await tester.enterText(find.byType(TextFormField).first, '06');
      await tester.enterText(find.byType(TextFormField).last, '45');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(picked, const TimeOfDay(hour: 6, minute: 45));
    });
  });
}
