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
  DateTime now = DateTime(2026, 11, 9, 6, 50);
  final states = <String>[];
  final stops = <String?>[];
  TrackerStep? last;

  Run(this.tracker);

  TrackerStep at(double meters, {int seconds = 10, String status = 'planificado', Set<int> passed = const {}, int next = 0, String? vehicle, int sensors = 1}) {
    now = now.add(Duration(seconds: seconds));
    final step = tracker.step(north(meters), now, TripInfo(status: status, passed: passed, nextStopIndex: next, vehicleState: vehicle, sensors: sensors));
    if (step.newState != null) {
      states.add(step.newState!);
      stops.add(step.stopId);
    }
    return last = step;
  }
}

WorkerTracker tracker({bool outbound = true, List<RouteStop>? stops}) => WorkerTracker(outbound: outbound, route: stops ?? route);

void main() {
  test('distancia (haversine)', () {
    expect(distanceMeters(north(0), north(1000)), closeTo(1000, 1));
  });

  group('Parada detectada por cercanía (docs/11 §11.65)', () {
    test('De camino a la parada más cercana, En la parada, Viajando y Dejado donde se baja', () {
      final r = Run(tracker());
      r.at(1400);
      r.at(1250);
      r.at(1040);
      // Su parada es la más cercana (Cine, la 2.ª), no la primera ni una «suya».
      expect(r.states, ['de_camino', 'en_parada']);
      expect(r.stops, ['2', '2']);
      // El vehículo llega y sale: se aleja de la parada a velocidad de vehículo.
      r.at(1080, passed: {0}, status: 'en_ejecucion', next: 1);
      r.at(1300, passed: {0}, status: 'en_ejecucion', next: 1);
      expect(r.states.last, 'viajando');
      expect(r.stops.last, '2', reason: 'subió en el Cine');
      expect(r.tracker.isSensor, isTrue);
      expect(r.tracker.stopName, isNull, reason: 'Viajando no muestra parada');
      // Sensor: la próxima parada empieza después de donde subió.
      var step = r.at(1600, passed: {0, 1}, status: 'en_ejecucion', next: 2);
      expect(step.vehicleState, 'en_movimiento');
      expect(step.nextStopIndex, 2);
      // Atraviesa Coppelia y sigue: la próxima es el Hospital.
      r.at(1990, passed: {0, 1}, status: 'en_ejecucion', next: 2);
      step = r.at(2300, passed: {0, 1}, status: 'en_ejecucion', next: 2);
      expect(step.nextStopIndex, 3);
      // Se baja en el Hospital: «Cálculos consecutivos» a velocidad humana en el radio.
      r.at(2990, passed: {0, 1, 2}, status: 'en_ejecucion', next: 3);
      for (var i = 0; i < 5; i++) {
        step = r.at(2992 + i.toDouble(), passed: {0, 1, 2}, status: 'en_ejecucion', next: 3);
        expect(step.newState, isNull);
      }
      expect(step.atStop, isTrue);
      step = r.at(2998, passed: {0, 1, 2}, status: 'en_ejecucion', next: 3);
      expect(step.newState, 'dejado');
      expect(step.stopId, '4');
      expect(step.finished, isTrue);
      expect(r.tracker.stopName, 'Hospital', reason: 'Mi estado: la parada donde se le dejó');
    });

    test('Dejado entre paradas cuando los demás sensores dicen que el vehículo sigue', () {
      final r = Run(tracker())..tracker.declare('viajando', stopId: '1');
      r.at(400, status: 'en_ejecucion', passed: {0}, next: 1);
      for (var i = 0; i < 6; i++) {
        r.at(400 + i.toDouble(), status: 'en_ejecucion', passed: {0}, next: 1, vehicle: 'en_movimiento', sensors: 3);
      }
      expect(r.states, ['dejado']);
      expect(r.stops.last, '1', reason: 'la parada más cercana');
    });

    test('Un vehículo detenido entre paradas no deja a nadie', () {
      final r = Run(tracker())..tracker.declare('viajando', stopId: '1');
      for (var i = 0; i < 10; i++) {
        r.at(500, status: 'en_ejecucion', passed: {0}, next: 1, vehicle: 'detenido', sensors: 2);
      }
      expect(r.states, isEmpty);
      expect(r.last!.vehicleState, 'detenido');
    });

    test('Su parada se recalcula: la más cercana de las que el vehículo no ha pasado', () {
      final r = Run(tracker());
      r.at(1300);
      expect(r.stops.last, '2');
      // El vehículo pasó por el Cine: ahora va hacia Coppelia. Pero estaba De camino al Cine: Retrasado.
      r.at(1290, passed: {0, 1}, status: 'en_ejecucion', next: 2);
      expect(r.states.last, 'retrasado');
      expect(r.stops.last, '2');
    });
  });

  group('No recogido y Retrasado (antes Botado y Dormido), en los dos sentidos', () {
    for (final outbound in [true, false]) {
      final name = outbound ? 'ida' : 'regreso';
      final stops = outbound ? route : route.reversed.toList();

      test('$name: En la parada y el vehículo pasa sin recogerle → No recogido', () {
        final r = Run(tracker(outbound: outbound, stops: stops));
        r.at(2010);
        expect(r.states, ['en_parada']);
        final index = stops.indexWhere((s) => s.id == '3');
        r.at(2015, status: 'en_ejecucion', passed: {for (var i = 0; i <= index; i++) i}, next: index + 1);
        expect(r.states.last, 'no_recogido');
        expect(r.stops.last, '3');
        // Final: aunque siga ahí o camine, no cambia; tras la Espera final deja de calcular.
        r.at(2030, status: 'en_ejecucion', passed: {for (var i = 0; i <= index; i++) i});
        expect(r.states.length, 2);
        final step = r.at(2030, seconds: 600, status: 'en_ejecucion', passed: {for (var i = 0; i <= index; i++) i});
        expect(step.finished, isTrue);
      });

      test('$name: De camino y el vehículo pasa antes de que llegue → Retrasado', () {
        final r = Run(tracker(outbound: outbound, stops: stops));
        r.at(2400);
        r.at(2300);
        expect(r.states, ['de_camino']);
        final index = stops.indexWhere((s) => s.id == '3');
        r.at(2200, status: 'en_ejecucion', passed: {for (var i = 0; i <= index; i++) i});
        expect(r.states.last, 'retrasado');
        // Llega luego a la parada: sigue Retrasado (final).
        r.at(2000, status: 'en_ejecucion', passed: {for (var i = 0; i <= index; i++) i});
        expect(r.states.last, 'retrasado');
        expect(r.tracker.stopName, 'Coppelia');
      });

      test('$name: sube en cualquier parada aunque el vehículo ya haya pasado otras', () {
        final r = Run(tracker(outbound: outbound, stops: stops));
        final index = stops.indexWhere((s) => s.id == '2');
        final before = {for (var i = 0; i < index; i++) i};
        r.at(1010, status: 'en_ejecucion', passed: before);
        expect(r.states, ['en_parada']);
        r.at(1050, status: 'en_ejecucion', passed: before);
        r.at(outbound ? 1300 : 700, status: 'en_ejecucion', passed: before);
        expect(r.states.last, 'viajando');
        expect(r.tracker.sensorNext, index + 1);
      });
    }

    test('Un No recogido que se aleja a velocidad de vehículo sí subió: Viajando', () {
      final r = Run(tracker());
      r.at(1000);
      r.at(1010, status: 'en_ejecucion', passed: {0, 1}, next: 2);
      expect(r.states.last, 'no_recogido');
      r.at(1300, status: 'en_ejecucion', passed: {0, 1}, next: 2);
      expect(r.states.last, 'viajando');
    });
  });

  test('El de la captura: viaje en ejecución, el vehículo pasó la parada 2 y él seguía En la parada 1', () {
    // 4.3.0: nunca pasó a Dormido ni Botado. Ahora: No recogido en cuanto se sabe que pasó.
    final r = Run(tracker())..tracker.declare('en_parada', stopId: '1');
    r.at(5);
    r.at(8, status: 'en_ejecucion', passed: {0, 1}, next: 2);
    expect(r.states, ['no_recogido']);
    expect(r.stops, ['1']);
  });

  test('No voy solo al alejarse de todas las paradas más allá de la Distancia abandono', () {
    final r = Run(tracker());
    r.at(-300);
    r.at(-600);
    expect(r.states, ['de_camino'], reason: 'aún cerca: sigue De camino');
    r.at(-1200);
    expect(r.states.last, 'no_voy');
    expect(r.last!.finished, isTrue);
    expect(r.stops.last, isNull);
  });

  test('Viaje cerrado: deja de calcular', () {
    final r = Run(tracker());
    r.at(100);
    expect(r.at(100, status: 'cancelado').finished, isTrue);
  });

  test('Guarda y recupera su estado (también los nombres viejos)', () {
    final r = Run(tracker());
    r.at(1400);
    r.at(1040);
    final copy = WorkerTracker.fromJson(r.tracker.toJson());
    expect(copy.state, 'en_parada');
    expect(copy.stopId, '2');
    expect(copy.lastPoint!.latitude, closeTo(north(1040).latitude, 1e-9));
    expect(WorkerTracker.fromJson({...r.tracker.toJson(), 'state': 'botado'}).state, 'no_recogido');
    expect(WorkerTracker.fromJson({...r.tracker.toJson(), 'state': 'dormido'}).state, 'retrasado');
    expect(WorkerTracker.fromJson({...r.tracker.toJson(), 'state': 'recogido'}).isSensor, isTrue);
  });

  test('Declarar No voy o Dejado termina el cálculo', () {
    final t = tracker()..declare('no_voy');
    expect(t.step(north(0), DateTime(2026), const TripInfo(status: 'planificado')).finished, isTrue);
  });
}
