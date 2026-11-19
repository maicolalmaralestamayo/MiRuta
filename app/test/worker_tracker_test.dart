import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/services/tracking/worker_tracker.dart';

/// Recorrido en línea recta hacia el norte: una parada cada kilómetro.
const base = GeoPoint(23.0, -82.0);
GeoPoint north(double meters) => GeoPoint(base.latitude + meters / 111195, base.longitude);

final route = [
  RouteStop('1', 'Parqueo', north(0)),
  RouteStop('2', 'Cine', north(1000)),
  RouteStop('3', 'Coppelia', north(2000)),
  RouteStop('4', 'Hospital', north(3000)),
];

class Run {
  final WorkerTracker tracker;
  DateTime now = DateTime(2026, 11, 19, 10, 20);
  final states = <String>[];
  final stops = <String?>[];
  TrackerStep? last;

  Run(this.tracker);

  TrackerStep at(double meters,
      {int seconds = 10,
      String status = 'planificado',
      Map<int, String> stopStates = const {},
      Set<int> left = const {},
      int next = 0,
      String? vehicle,
      bool atStop = false,
      int sensors = 1}) {
    now = now.add(Duration(seconds: seconds));
    final info = TripInfo(status: status, stopStates: stopStates, left: left, nextStopIndex: next, vehicleState: vehicle, vehicleAtStop: atStop, sensors: sensors);
    final step = tracker.step(north(meters), now, info);
    if (step.newState != null) {
      states.add(step.newState!);
      stops.add(step.stopId);
    }
    return last = step;
  }
}

WorkerTracker tracker({bool outbound = true, int consecutive = 3}) => WorkerTracker(outbound: outbound, route: route, config: TrackerConfig(consecutive: consecutive));

void main() {
  test('distancia (haversine)', () {
    expect(distanceMeters(north(0), north(1000)), closeTo(1000, 1));
  });

  group('Estados del trabajador, versión definitiva (docs/11 §11.67)', () {
    test('Fuera de itinerario a más de 300 m de todas las paradas; Acercándose a Parada; En Parada a 100 m o menos', () {
      final r = Run(tracker());
      r.at(1500);
      expect(r.states, ['fuera_itinerario']);
      expect(r.stops, [null]);
      // Entra en los 300 m del Cine caminando (1,5 m/s) y la distancia baja de forma consecutiva.
      r.at(1290, seconds: 140);
      r.at(1260, seconds: 20);
      r.at(1230, seconds: 20);
      r.at(1200, seconds: 20);
      expect(r.states.last, 'acercandose');
      expect(r.stops.last, '2');
      r.at(1080, seconds: 80);
      expect(r.states.last, 'en_parada');
      expect(r.stops.last, '2');
      expect(r.tracker.stopName, 'Cine');
    });

    test('Alejándose de Parada: la distancia tiende a aumentar a velocidad humana', () {
      final r = Run(tracker());
      r.at(1150);
      for (final m in <double>[1180.0, 1210, 1240, 1270]) {
        r.at(m, seconds: 20);
      }
      expect(r.states.last, 'alejandose');
      expect(r.stops.last, '2');
      // Se aleja más de 300 m de todas: Fuera de itinerario.
      r.at(1400, seconds: 90);
      expect(r.states.last, 'fuera_itinerario');
    });

    test('Al iniciarse el viaje: En Parada en la primera parada de recogida y se aleja de forma consecutiva a velocidad no humana → Viajando', () {
      final r = Run(tracker());
      r.at(20);
      expect(r.states, ['en_parada']);
      // 30 km/h ≈ 83 m cada 10 s, alejándose del Parqueo.
      r.at(110);
      r.at(195);
      expect(r.states.last, 'en_parada', reason: 'hacen falta los Cálculos consecutivos');
      r.at(280);
      expect(r.states.last, 'viajando');
      expect(r.stops.last, '1');
      expect(r.tracker.isSensor, isTrue);
      expect(r.tracker.stopName, isNull, reason: 'Viajando no muestra parada');
    });

    test('En otra parada solo sube si está Recogida (o si aún no hay datos del vehículo)', () {
      // Con datos del vehículo y la parada En espera: un coche que pasa no es el vehículo.
      final r = Run(tracker());
      r.at(1010, status: 'en_ejecucion', vehicle: 'en_movimiento', next: 1);
      for (final m in <double>[1100.0, 1190, 1280]) {
        r.at(m, status: 'en_ejecucion', vehicle: 'en_movimiento', next: 1);
      }
      expect(r.states, ['en_parada']);

      // La parada está Recogida (el vehículo se detuvo en ella): sube.
      final s = Run(tracker());
      s.at(1010, status: 'en_ejecucion', vehicle: 'detenido', atStop: true, next: 1, stopStates: {0: 'recogida', 1: 'recogida'}, left: {0});
      for (final m in <double>[1100.0, 1190, 1280]) {
        s.at(m, status: 'en_ejecucion', vehicle: 'en_movimiento', next: 1, stopStates: {0: 'recogida', 1: 'recogida'}, left: {0});
      }
      expect(s.states.last, 'viajando');
      expect(s.stops.last, '2');

      // Sin datos del vehículo (ningún sensor) también: si no, nadie sería el primero.
      final t = Run(tracker());
      t.at(1010, status: 'en_ejecucion', next: 1, sensors: 0);
      for (final m in <double>[1100.0, 1190, 1280]) {
        t.at(m, status: 'en_ejecucion', next: 1, sensors: 0);
      }
      expect(t.states.last, 'viajando');
    });

    test('No recogido: la parada dejó de estar En espera, el vehículo la dejó atrás y él siguió En Parada', () {
      final r = Run(tracker());
      r.at(1020, status: 'en_ejecucion', next: 1, vehicle: 'en_movimiento');
      // El vehículo se detiene en ella: sigue En Parada (puede subir).
      r.at(1022, status: 'en_ejecucion', next: 1, vehicle: 'detenido', atStop: true, stopStates: {0: 'recogida', 1: 'recogida'}, left: {0});
      expect(r.states, ['en_parada']);
      // Se va sin él.
      r.at(1023, status: 'en_ejecucion', next: 2, vehicle: 'en_movimiento', stopStates: {0: 'recogida', 1: 'recogida'}, left: {0, 1});
      expect(r.states.last, 'no_recogido');
      expect(r.stops.last, '2');
      // Va caminando hacia la parada siguiente y la espera allí: En Parada otra vez.
      r.at(1400, seconds: 300, status: 'en_ejecucion', next: 2, vehicle: 'en_movimiento', stopStates: {0: 'recogida', 1: 'recogida'}, left: {0, 1});
      expect(r.states.last, 'no_recogido', reason: 'se conserva hasta llegar a otra parada En espera');
      r.at(1950, seconds: 400, status: 'en_ejecucion', next: 2, vehicle: 'en_movimiento', stopStates: {0: 'recogida', 1: 'recogida'}, left: {0, 1});
      expect(r.states.last, 'en_parada');
      expect(r.stops.last, '3');
    });

    test('Llegada tarde: la parada cambió de estado antes de que llegara a En Parada', () {
      final r = Run(tracker());
      r.at(1290);
      for (final m in <double>[1260.0, 1230, 1200]) {
        r.at(m, seconds: 20);
      }
      expect(r.states.last, 'acercandose');
      r.at(1170, seconds: 20, status: 'en_ejecucion', next: 2, vehicle: 'en_movimiento', stopStates: {0: 'recogida', 1: 'volada'}, left: {0, 1});
      expect(r.states.last, 'llegada_tarde');
      expect(r.stops.last, '2');
      // Llega a la parada ya pasada: sigue Llegada tarde.
      r.at(1050, seconds: 60, status: 'en_ejecucion', next: 2, vehicle: 'en_movimiento', stopStates: {0: 'recogida', 1: 'volada'}, left: {0, 1});
      expect(r.states.last, 'llegada_tarde');
    });

    test('Dejado: a velocidad humana y la distancia a la parada más cercana tiende a aumentar', () {
      final r = Run(tracker());
      r.tracker.declare('viajando', stopId: '1');
      // En el vehículo hacia el Hospital.
      r.at(2500, status: 'en_ejecucion', next: 3, vehicle: 'en_movimiento');
      var step = r.at(2990, status: 'en_ejecucion', next: 3, vehicle: 'detenido');
      expect(step.isSensor, isTrue);
      expect(step.inRadius, isTrue);
      // Detenido en la parada (velocidad humana pero sin alejarse): sigue Viajando.
      for (var i = 0; i < 4; i++) {
        step = r.at(2995, status: 'en_ejecucion', next: 3, vehicle: 'detenido');
        expect(step.newState, isNull);
      }
      expect(step.atStop, isTrue);
      // Se va caminando: la distancia al Hospital aumenta.
      for (final m in <double>[3020.0, 3045, 3070]) {
        r.at(m, status: 'en_ejecucion', next: 3, vehicle: 'detenido');
      }
      expect(r.states.last, 'dejado');
      expect(r.stops.last, '4');
      expect(r.tracker.finished, isTrue);
      expect(r.tracker.stopName, 'Hospital', reason: 'en Dejado, donde se le dejó');
    });

    test('Sensor: velocidad del vehículo, próxima parada y si pasó por su radio', () {
      final r = Run(tracker());
      r.tracker.declare('viajando', stopId: '1');
      r.at(500, status: 'en_ejecucion', next: 1);
      var step = r.at(990, status: 'en_ejecucion', next: 1);
      expect(step.vehicleState, 'en_movimiento');
      expect(step.inRadius, isTrue);
      expect(step.speedKmh, closeTo(176, 1));
      step = r.at(1300, status: 'en_ejecucion', next: 1);
      expect(step.nextStopIndex, 2, reason: 'entró en el radio del Cine y salió');
      expect(step.inRadius, isFalse);
    });
  });

  group('A mano (docs/11 §11.67)', () {
    test('el estado manual se respeta hasta que el cálculo detecta un cambio real', () {
      final r = Run(tracker());
      r.at(1500);
      expect(r.states, ['fuera_itinerario']);
      // Se marca En Parada en el Cine estando lejos: la posición no cambia → se respeta.
      r.tracker.declare('en_parada', stopId: '2', manual: true);
      r.at(1502);
      r.at(1498);
      expect(r.states, ['fuera_itinerario']);
      expect(r.tracker.state, 'en_parada');
      expect(r.tracker.manual, isTrue);
      // El GPS lo ve alejarse del Cine a velocidad de vehículo: Viajando (no hay datos del vehículo).
      for (final m in <double>[1590.0, 1680, 1770]) {
        r.at(m, status: 'en_ejecucion', next: 1, sensors: 0);
      }
      expect(r.states.last, 'viajando');
      expect(r.tracker.manual, isFalse);
    });

    test('un cambio real de la posición sustituye al manual', () {
      final r = Run(tracker());
      r.at(1500);
      r.tracker.declare('llegada_tarde', stopId: '2', manual: true);
      r.at(1500);
      expect(r.tracker.state, 'llegada_tarde');
      // Llega caminando al radio del Coppelia (En espera): En Parada.
      r.at(1950, seconds: 400);
      expect(r.tracker.state, 'en_parada');
      expect(r.tracker.stopId, '3');
    });

    test('No viajaré solo a mano: nunca se calcula y termina el cálculo', () {
      final r = Run(tracker());
      r.tracker.declare('no_viajare', manual: true);
      expect(r.tracker.finished, isTrue);
      expect(r.tracker.stopId, isNull);
      expect(r.at(1000).finished, isTrue);
      expect(r.states, isEmpty);
    });
  });

  test('Viaje cerrado o nada más que esperar: deja de calcular', () {
    final r = Run(tracker());
    expect(r.at(1500, status: 'terminado').finished, isTrue);
    final s = Run(tracker());
    s.at(5000, status: 'en_ejecucion');
    final all = {0: 'recogida', 1: 'volada', 2: 'omitida', 3: 'recogida'};
    expect(s.at(5000, status: 'en_ejecucion', stopStates: all, left: {0, 1, 2, 3}, next: 4).finished, isTrue);
  });

  test('se guarda y se recupera entre cálculos', () {
    final r = Run(tracker());
    r.at(1290);
    r.at(1260);
    r.tracker.declare('en_parada', stopId: '2', manual: true);
    final copy = WorkerTracker.fromJson(r.tracker.toJson());
    expect(copy.state, 'en_parada');
    expect(copy.stopId, '2');
    expect(copy.manual, isTrue);
    expect(copy.lastPoint!.latitude, closeTo(north(1260).latitude, 1e-9));
    expect(copy.config.approachRadius, 300);
    expect(copy.toJson()['version'], 50);
  });
}
