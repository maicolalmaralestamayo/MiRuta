import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/ui/stats/statistic.dart';

/// Comprueba que los modelos de la app interpretan respuestas reales de la API
/// (test/fixtures se generan con un escenario completo contra el servidor).
JsonApiDocument fixture(String name) =>
    JsonApiDocument.fromJson(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('mi cuenta con su trabajador, Entidad, jerarquía, roles e hijos', () {
    final me = Me.from(fixture('me').resource);
    expect(me.fullName, 'Lucía María Pérez García');
    expect(me.username, 'lucia.perez');
    expect(me.isAdmin, isFalse);
    expect(me.needsEntity, isFalse);
    expect(me.mustChangePassword, isFalse);
    expect(me.account.passwordExpiresAt, isNotNull);
    expect(me.entity?.abbreviation, 'PRUEBA');
    expect(me.pass, 101);
    expect(me.sex, 'F');
    expect(me.rank?.name, 'Trabajador civil');
    expect(me.itineraryId, isNotNull);
    expect(me.stopId, isNotNull);
    expect(me.childrenCount, 1);
    expect(me.roles.isDriver, isFalse);
  });

  test('viaje con vehículo, tipo, chofer y ocupación', () {
    final trip = Trip.from(fixture('trip').resource);
    expect(trip.isConfirmed, isTrue);
    expect(trip.itineraryName, 'Ruta Este');
    expect(trip.vehiclePlate, 'B123456');
    expect(trip.vehicleTypeName, 'Guagua');
    expect(trip.driverName, 'Carlos Chofer');
    expect(trip.totalCapacity, 1);
    expect(trip.seats, 1);
    expect(trip.expectedPassengers, 1, reason: 'el chofer es miembro y no cuenta');
    expect(trip.expectedChildren, 1);
    expect(trip.occupancyLevel, 'normal', reason: 'los niños van cargados y no ocupan plaza');
    expect(trip.departureStopId, isNotNull);
    expect(Trip.fromJson(trip.toJson()).departsAt, trip.departsAt);
  });

  test('paradas del itinerario en orden', () {
    final links = fixture('itinerary_stops').resources.map(ItineraryStop.from).toList();
    expect(links.map((l) => l.stop!.landmark), ['Empresa', 'Parque', 'Hospital']);
    expect(links.first.stop!.address, 'Empresa, Calle 1 entre A y B');
    final itinerary = Itinerary.from(fixture('itinerary').resource);
    expect(itinerary.departureStopId, links.first.stopId);
    expect(itinerary.returnStopId, links.last.stopId);
  });

  test('trayecto con posición combinada y paso por paradas', () {
    final leg = TripLeg.from(fixture('trip_leg').resource);
    expect(leg.isReturn, isTrue);
    expect(leg.activeSensors, 1);
    expect(leg.latitude, closeTo(23.1199, 0.0001));
    expect(leg.stopPasses, hasLength(1));
  });

  test('pasajeros por parada', () {
    final passengers = fixture('passengers').resources.map(Passenger.from).toList();
    expect(passengers, hasLength(1));
    expect(passengers.first.boarded, isTrue);
    expect(passengers.first.boardingMethod, 'self');
    expect(passengers.first.boardedChildren, 1);
    expect(passengers.first.worker.rank?.name, 'Trabajador civil');
    expect(passengers.first.worker.fullName, 'Lucía María Pérez García');
    expect(passengers.first.position, 1);
  });

  test('solicitudes, hijos, avisos, mensajes y conversaciones', () {
    final applications = fixture('applications').resources.map(Application.from).toList();
    expect(applications.map((a) => a.type), containsAll(['itinerary_membership', 'child_addition']));
    expect(applications.firstWhere((a) => a.type == 'child_addition').childName, 'Pepito Juan Pérez García');
    expect(applications.firstWhere((a) => a.type == 'itinerary_membership').resolverName, 'Teresa Jefa');
    expect(applications.firstWhere((a) => a.type == 'itinerary_membership').itineraryName, 'Ruta Este');

    final child = Child.from(fixture('children').resource);
    expect(child.declared, isTrue);
    expect(child.birthDate, '2015-03-05');
    expect(child.fullName, 'Pepito Juan Pérez García');
    expect(child.eligibleUntil, '2031-08-31');

    expect(fixture('notices').resources.map(Notice.from).first.title, isNotEmpty);
    final message = Message.from(fixture('trip_messages').resource);
    expect(message.authorName, 'Lucía Pérez');
    expect(message.authorId, isNotNull);
    final conversation = Conversation.from(fixture('conversations').resource);
    expect(conversation.recipient, 'itinerary_chiefs');
    expect(conversation.topicName, 'Reportar un problema');
    expect(conversation.messageCount, 1);
    expect(conversation.guest, isFalse);
    expect(conversation.openedByName, 'Lucía María Pérez García');
  });

  test('ajustes y definiciones', () {
    final settings = {for (final r in fixture('user_settings').resources) r.id: r.string('value')};
    expect(settings['departure_notice_minutes_before'], '60');
    final definitions = {for (final r in fixture('setting_definitions').resources) r.id: SettingDefinition.from(r)};
    expect(definitions['stop_notice_scope']!.options, hasLength(3));
    expect(definitions['trips_poll_background_minutes']!.minSetting, 'min_background_poll_minutes');
  });

  test('estadísticas y viaje en marcha', () {
    final statistic = Statistic.from(fixture('statistic').resource);
    expect(statistic.columns.map((c) => c.key), ['status', 'trips']);
    expect(statistic.chartSeries()!.labels, contains('Confirmado'));
    final live = Statistic.from(fixture('live_trip').resource);
    expect(live.rows.first['boarded'], 1);
    expect(live.rows.first['children'], 1);
  });

  test('vehículo y trabajadores', () {
    final vehicle = Vehicle.from(fixture('vehicle').resource);
    expect(vehicle.totalCapacity, 1);
    expect(vehicle.vehicleType?.name, 'Guagua');
    final workers = fixture('workers').resources.map(Worker.from).toList();
    expect(workers, hasLength(3), reason: 'el Administrador no es trabajador');
    expect(workers.every((w) => w.entity?.abbreviation == 'PRUEBA'), isTrue);
    expect(workers.firstWhere((w) => w.firstName == 'Teresa').roles.isTransportChief, isTrue);
    expect(workers.firstWhere((w) => w.firstName == 'Carlos').roles.isDriver, isTrue);
    expect(workers.map((w) => w.pass), containsAll([101, 102, 103]));
    expect(Entity.from(fixture('entity_lookup').resource).name, 'Empresa de prueba');
  });
}
