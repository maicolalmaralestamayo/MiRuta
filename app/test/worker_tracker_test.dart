import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/services/tracking/worker_tracker.dart';

/// Recorrido en línea recta hacia el norte: una parada cada kilómetro.
const base = GeoPoint(23.0, -82.0);
GeoPoint north(double meters) => GeoPoint(base.latitude + meters / 111195, base.longitude);

final route = [RouteStop('1', 'Parqueo', north(0)), RouteStop('2', 'Cine', north(1000)), RouteStop('3', 'Coppelia', north(2000))];

class Run {
  final WorkerTracker tracker;
  DateTime now = DateTime(2026, 11, 9, 6, 50);
  final states = <String>[];
  TrackerStep? last;

  Run(this.tracker);

  TrackerStep at(double meters, {int seconds = 10, String status = 'planificado', bool passed = false, int next = 0}) {
    now = now.add(Duration(seconds: seconds));
    final step = tracker.step(north(meters), now, TripInfo(status: status, vehiclePassedMyStop: passed, nextStopIndex: next));
    if (step.newState != null) states.add(step.newState!);
    return last = step;
  }
}

void main() {
  test('distancia (haversine)', () {
    expect(distanceMeters(north(0), north(1000)), closeTo(1000, 1));
  });

  group('Ida', () {
    test('De camino → En la parada → Viajando → Dejado en su parada', () {
      final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
      r.at(-500);
      r.at(-300);
      r.at(-40);
      expect(r.states, ['de_camino', 'en_parada']);
      // El vehículo sale: se aleja de la primera parada a más de 10 km/h.
      r.at(60);
      r.at(200, status: 'en_ejecucion');
      expect(r.states.last, 'viajando');
      expect(r.tracker.isSensor, isTrue);
      // Va en el vehículo: sensor (en movimiento) y avance de la próxima parada.
      var step = r.at(900, status: 'en_ejecucion', next: 1);
      expect(step.vehicleState, 'en_movimiento');
      r.at(1000, status: 'en_ejecucion', next: 1);
      step = r.at(1300, status: 'en_ejecucion', next: 1);
      expect(step.nextStopIndex, 2, reason: 'entró en el radio de la 2.ª parada y salió');
      // Se baja en su parada: 6 cálculos a velocidad humana dentro del radio.
      r.at(1985, status: 'en_ejecucion', next: 2);
      for (var i = 0; i < 5; i++) {
        step = r.at(1990 + i.toDouble(), status: 'en_ejecucion', next: 2);
        expect(step.newState, isNull);
      }
      expect(step.vehicleState, 'detenido');
      expect(step.atStop, isTrue);
      step = r.at(1996, status: 'en_ejecucion', next: 2);
      expect(step.newState, 'dejado');
      expect(step.stopId, '3');
      expect(step.finished, isTrue);
    });

    test('Viajando solo pasa a Dejado (semidefinitivo)', () {
      final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
      r.at(-10);
      r.at(200);
      expect(r.tracker.state, 'viajando');
      r.at(-10, status: 'en_ejecucion');
      expect(r.tracker.state, 'viajando');
    });

    test('Se aleja a pie: No voy a viajar, definitivo a más de 1 km', () {
      final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
      r.at(-300);
      r.at(-330);
      expect(r.tracker.state, 'no_voy');
      expect(r.tracker.finished, isFalse, reason: 'entre 100 m y 1 km aún puede cambiar');
      r.at(-280);
      expect(r.tracker.state, 'de_camino');
      r.at(-600, seconds: 120);
      r.at(-1100, seconds: 180);
      expect(r.tracker.state, 'no_voy');
      expect(r.tracker.finished, isTrue);
    });

    test('Tolerancia del GPS: sin moverse más de 20 m conserva el estado', () {
      final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
      r.at(-500);
      r.at(-510);
      r.at(-495);
      expect(r.states, ['de_camino']);
    });

    test('Al empezar el viaje, quien no está en la parada no va', () {
      final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
      r.at(-500);
      final step = r.at(-450, status: 'en_ejecucion');
      expect(step.newState, 'no_voy');
      expect(step.finished, isTrue);
    });
  });

  group('Regreso (de la última a la primera)', () {
    // En el regreso el recorrido va al revés; su parada es la 2.ª del itinerario.
    final back = route.reversed.toList();

    test('En la parada y sale a velocidad de vehículo: Recogido (sensor)', () {
      final r = Run(WorkerTracker(outbound: false, route: back, myIndex: 1));
      r.at(1300);
      r.at(1050);
      expect(r.states, ['de_camino', 'en_parada']);
      r.at(850, passed: true, status: 'en_ejecucion');
      expect(r.tracker.state, 'recogido');
      expect(r.tracker.isSensor, isTrue);
    });

    test('Botado: estaba en la parada, pasó el vehículo y no lo recogió', () {
      final r = Run(WorkerTracker(outbound: false, route: back, myIndex: 1));
      r.at(1020);
      for (var i = 0; i < 6; i++) {
        r.at(1010, passed: true, status: 'en_ejecucion');
      }
      expect(r.tracker.state, 'botado');
      r.at(1010, seconds: 601, passed: true, status: 'en_ejecucion');
      expect(r.tracker.finished, isTrue, reason: 'pasada la espera final deja de calcular');
    });

    test('Dormido: llega a la parada después de que pasara el vehículo', () {
      final r = Run(WorkerTracker(outbound: false, route: back, myIndex: 1));
      r.at(1400);
      r.at(1300, passed: true, status: 'en_ejecucion');
      r.at(1050, passed: true, status: 'en_ejecucion');
      expect(r.tracker.state, 'dormido');
    });

    test('Termina el viaje: deja de calcular', () {
      final r = Run(WorkerTracker(outbound: false, route: back, myIndex: 1));
      r.at(1400);
      expect(r.at(1300, status: 'terminado').finished, isTrue);
    });
  });

  test('se guarda y se recupera entre cálculos', () {
    final r = Run(WorkerTracker(outbound: true, route: route, myIndex: 2));
    r.at(-40);
    final copy = WorkerTracker.fromJson(r.tracker.toJson());
    expect(copy.state, 'en_parada');
    expect(copy.reachedStop, isTrue);
    expect(copy.route.length, 3);
    expect(copy.lastPoint!.latitude, closeTo(r.tracker.lastPoint!.latitude, 1e-9));
  });

  test('declarado a mano', () {
    final t = WorkerTracker(outbound: true, route: route, myIndex: 2)..declare('no_voy');
    expect(t.finished, isTrue);
  });
}
