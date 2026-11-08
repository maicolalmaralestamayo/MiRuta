import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';

Resource one(Map<String, dynamic> json) => JsonApiDocument.fromJson(json).resource;

void main() {
  test('GET me: rol, jefatura y pertenencias (docs/13 §13.4)', () {
    final me = Me.from(one({
      'data': {
        'type': 'users',
        'id': '2',
        'attributes': {'username': 'ana', 'firstName': 'Ana', 'firstSurname': 'García', 'secondSurname': 'Pérez', 'fullName': 'Ana García Pérez', 'isAdmin': false, 'identityCard': '90010112345'},
        'meta': {
          'role': 'jefe',
          'chiefItineraryId': '1',
          'memberships': [
            {
              'workerId': '2',
              'active': true,
              'isChief': true,
              'entity': {'id': '1', 'abbreviation': 'UMIM', 'name': 'Unidad Militar', 'workerCount': 2},
              'itinerary': {'id': '1', 'name': 'Ruta Playa', 'workerCount': 2},
              'stop': {'id': '2', 'landmark': 'Cine', 'street': 'Calle 1', 'latitude': 23.01, 'longitude': -82.0},
            },
          ],
        },
      },
    }));
    expect(me.role, Role.jefe);
    expect(me.manages, isTrue);
    expect(me.isChiefOf('1'), isTrue);
    expect(me.chiefMembership!.itineraryName, 'Ruta Playa');
    expect(me.seesTrips, isTrue);
    expect(me.toJson()['travelItineraryIds'], ['1']);
  });

  test('sin Entidad no ve viajes', () {
    final me = Me.from(one({'data': {'type': 'users', 'id': '3', 'attributes': {}, 'meta': {'role': 'trabajador', 'memberships': []}}}));
    expect(me.hasEntity, isFalse);
    expect(me.seesTrips, isFalse);
  });

  test('línea del recorrido (trips/{id}/live)', () {
    final live = TripLive.from(one({
      'data': {
        'type': 'trip-lives',
        'id': '15',
        'attributes': {
          'direction': 'regreso',
          'status': 'en_ejecucion',
          'vehicle': {'state': 'detenido', 'atStop': true, 'nextStopIndex': 1, 'longDetention': false, 'detentionCause': null},
          'sensors': 3,
          'inVehicle': {'workers': 12, 'children': 2, 'total': 14, 'capacity': 60},
          'expectedPassengers': 38,
          'notGoing': 1,
          'stops': [
            {'index': 0, 'stopId': '9', 'landmark': 'Reparto', 'passed': true, 'passedAt': '2026-11-09T17:31:00-05:00', 'expected': 5, 'counts': {'botado': 1}, 'mine': false},
            {'index': 1, 'stopId': '7', 'landmark': 'Coppelia', 'passed': false, 'expected': 4, 'counts': {}, 'mine': true},
          ],
          'myState': {'state': 'en_parada', 'stopId': '7', 'childrenCount': 0, 'sensor': false},
        },
      },
    }));
    expect(live.outbound, isFalse);
    expect(live.sensors, 3);
    expect(live.inVehicleWorkers + live.inVehicleChildren, 14);
    expect(live.stops.first.counts, {'botado': 1});
    expect(live.myStop!.landmark, 'Coppelia');
    expect(WorkerState.name(live.myState), 'En la parada');
  });

  test('parada con sus itinerarios y dirección', () {
    final stop = Stop.from(one({
      'data': {
        'type': 'stops',
        'id': '7',
        'attributes': {'landmark': 'Coppelia', 'street': 'Calle 23', 'crossStreet1': 'K', 'crossStreet2': 'L', 'latitude': 23.1, 'longitude': -82.3},
        'meta': {
          'itineraries': [
            {'itineraryStopId': '3', 'itineraryId': '1', 'name': 'Ruta Playa', 'entityId': '1', 'position': 4},
          ],
        },
      },
    }));
    expect(stop.address, 'Calle 23 • entre K y L');
    expect(stop.positionIn('1'), 4);
    expect(stop.linkIn('1')!.itineraryStopId, '3');
  });

  test('carné de identidad: sexo y nacimiento', () {
    expect(IdentityCard.birthDate('85031512345'), DateTime(1985, 3, 15));
    expect(IdentityCard.sex('85031512345'), 'M');
    expect(IdentityCard.validate('123'), isNotNull);
    expect(sexAndBirth('M', DateTime(1985, 3, 15)), 'Masculino • vie. 15-03-85');
  });

  test('ocupación del viaje', () {
    final trip = Trip(id: '1', direction: 'ida', date: DateTime(2026, 11, 9), departureTime: '07:00', departsAt: DateTime(2026, 11, 9, 7), status: 'planificado', itineraryId: '1', expectedPassengers: 45, capacity: 60);
    expect(trip.occupancy, '45 de 60 • Normal');
    expect(trip.title, 'Viaje de ida');
  });
}
