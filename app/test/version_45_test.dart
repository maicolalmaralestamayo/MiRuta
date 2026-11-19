import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/ui/widgets/busy.dart';

/// Versión 4.5.0 (docs/11 §11.66): simulador de trabajadores.
void main() {
  group('Crear Simulación', () {
    test('por omisión 70 / 10 / 10 / 10 y vehículo simulado; falta el itinerario', () {
      final input = SimulationInput();
      expect([input.normal, input.late, input.leftBehind, input.notGoing], [70, 10, 10, 10]);
      expect(input.vehicleMode, SimulationInput.simulatedVehicle);
      expect(input.error, 'Elija el itinerario.');
      input.itineraryId = '3';
      expect(input.error, isNull);
      expect(input.attributes(), {
        'direction': 'ida', 'workers': 10, 'vehicleMode': 'simulado', 'normal': 70, 'late': 10, 'leftBehind': 10, 'notGoing': 10, 'speedFactor': 1,
      });
    });

    test('los porcentajes suman 100 y la cantidad va de 1 a 60', () {
      final input = SimulationInput()..itineraryId = '1';
      input.normal = 60;
      expect(input.error, contains('suman 90'));
      input.normal = 70;
      input.workers = 0;
      expect(input.error, contains('de 1 a 60'));
      input.workers = 61;
      expect(input.error, isNotNull);
      input.workers = 5;
      input.vehicleMode = SimulationInput.realVehicle;
      expect(input.error, isNull);
      expect(input.attributes().containsKey('speedFactor'), isFalse, reason: 'con vehículo real no hay factor de velocidad');
    });

    test('spinners con el nombre CRUD', () {
      expect(progressiveLabel('Crear Simulación'), 'Creando Simulación');
      expect(progressiveLabel('Eliminar Simulación'), 'Eliminando Simulación');
      expect(progressiveLabel('Consultar Simulación'), 'Consultando Simulación');
    });
  });

  group('Estado de la simulación', () {
    test('cantidades por estado, sin informar, tiempo y vehículo', () {
      final s = WorkerSimulation.from(Resource(type: 'simulations', id: '7', attributes: const {
        'itineraryName': 'Ruta Playa', 'direction': 'regreso', 'vehicleMode': 'simulado', 'workers': 10, 'speedFactor': 2,
        'status': 'en_curso', 'counts': {'dejado': 3, 'viajando': 4, 'no_recogido': 1}, 'notReported': 2, 'sensors': 3,
        'elapsedSeconds': 125, 'tripStatus': 'en_ejecucion', 'myState': 'en_parada', 'vehicle': {'text': 'En Parada 2'},
      }, relationships: const {
        'trip': {'data': {'type': 'trips', 'id': '40'}},
      }));
      expect(s.running, isTrue);
      expect(s.simulatedVehicle, isTrue);
      expect(s.tripId, '40');
      expect(s.countsText, '1 No recogido • 4 Viajando • 3 Dejados • 2 sin informar');
      expect(s.elapsedText, '2 min 05 s');
      expect(s.vehicleText, 'En Parada 2');
      expect(WorkerSimulation.from(Resource(type: 'simulations', id: '1')).countsText, 'Sin informes aún');
    });

    test('el viaje de prueba se marca como Simulación', () {
      final trip = Trip.from(Resource(type: 'trips', id: '1', attributes: const {'direction': 'ida', 'status': 'planificado', 'simulation': true}));
      expect(trip.simulation, isTrue);
      expect(Trip.from(Resource(type: 'trips', id: '2', attributes: const {'direction': 'ida'})).simulation, isFalse);
    });
  });
}
