import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/models/models.dart';
import 'package:mitransporte/ui/stats/statistic.dart';

/// Comprueba que los modelos de la app interpretan respuestas reales de la
/// API 3.0 (test/fixtures se generan con tools/fixtures/generate_app_fixtures.py
/// contra el servidor, con un escenario completo).
JsonApiDocument fixture(String name) =>
    JsonApiDocument.fromJson(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('mi persona, sus dos Entidades, itinerario, parada, roles y permisos', () {
    final me = Me.from(fixture('me').resource);
    expect(me.fullName, 'Lucía María Pérez García');
    expect(me.username, 'lucia');
    expect(me.isAdmin, isFalse);
    expect(me.mustChangePassword, isFalse);
    expect(me.person.passwordExpiresAt, isNotNull);
    expect(me.person.identityCard, '90052002130');
    expect(me.person.sex, 'F');
    expect(me.person.birthDate, '1990-05-20');
    expect(me.person.entitiesLine, 'DOS • PRUEBA');
    expect(me.memberships, hasLength(2));

    final prueba = me.memberships.firstWhere((m) => m.entity.abbreviation == 'PRUEBA');
    expect(prueba.entity.name, 'Empresa de prueba');
    expect(prueba.entity.workerCount, 3);
    expect(prueba.itinerary?.name, 'Ruta Este');
    expect(prueba.stop?.landmark, 'Parque');
    expect(prueba.stop?.street, 'Calle 2');
    expect(prueba.hasItinerary, isTrue);
    expect(prueba.roles.single.isDefault, isTrue);
    expect(prueba.extraRoles, isEmpty, reason: 'Trabajador se muestra aparte');
    expect(me.membershipIn('2')?.hasItinerary, isFalse);
    expect(me.isMemberOf(prueba.itineraryId), isTrue);
    expect(me.stopIdIn(prueba.itineraryId), prueba.stopId);

    // Solo lo propio: no ve nada de gestión.
    expect(me.permissions.canAnywhere(Op.tripsView, includeOwn: true), isTrue);
    expect(me.canAnywhere(Op.tripsView), isFalse);
    expect(me.can(Op.tripsView, entityId: '1'), isFalse, reason: 'own no cuenta en can()');
    expect(me.permissions.canOwn(Op.tripsView, '1'), isTrue);
  });

  test('Administradora sin Entidad: todo en todas', () {
    final me = Me.from(fixture('me_admin').resource);
    expect(me.isAdmin, isTrue);
    expect(me.hasEntity, isFalse);
    expect(me.person.entitiesLine, 'Sin Entidad');
    expect(me.can(Op.maintenanceRun), isTrue);
    expect(me.can(Op.vehiclesManage, entityId: '99'), isTrue);
  });

  test('Jefa de Transporte y de itinerario: permisos por Entidad e itinerario', () {
    final me = Me.from(fixture('me_chief').resource);
    final membership = me.memberships.single;
    expect(membership.extraRoles.map((r) => r.name), containsAll(['Jefe de Transporte', 'Jefe de itinerario']));
    final itineraryChief = membership.extraRoles.firstWhere((r) => r.name == 'Jefe de itinerario');
    expect(itineraryChief.itineraryName, 'Ruta Este');
    expect(me.can(Op.vehiclesManage, entityId: membership.entityId), isTrue);
    expect(me.can(Op.vehiclesManage, entityId: '2'), isFalse);
    expect(me.can(Op.vehiclesManage), isFalse, reason: 'sin Entidad solo vale «all»');
    expect(me.can(Op.membersApprove, entityId: membership.entityId, itineraryId: itineraryChief.itineraryId), isTrue);
    expect(me.can(Op.membersApprove, itineraryId: itineraryChief.itineraryId), isTrue, reason: 'la Entidad se deduce del itinerario');
    expect(me.can(Op.membersApprove, entityId: membership.entityId, itineraryId: '999'), isFalse);
    expect(me.can(Op.entitiesManage, entityId: membership.entityId), isFalse);
    expect(me.permissions.entitiesFor(Op.tripsPlan), {membership.entityId});
  });

  test('viaje con vehículo, tipo, chofer (pertenencia), Entidad y ocupación', () {
    final trip = Trip.from(fixture('trip').resource);
    expect(trip.isConfirmed, isTrue);
    expect(trip.itineraryName, 'Ruta Este');
    expect(trip.entityId, '1');
    expect(trip.vehiclePlate, 'B123456');
    expect(trip.vehicleTypeName, 'Guagua');
    expect(trip.driverName, 'Carlos Chofer');
    expect(trip.driverId, '3');
    expect(trip.totalCapacity, 1);
    expect(trip.expectedPassengers, 1, reason: 'el chofer es miembro y no cuenta; los niños no se esperan');
    expect(trip.occupancyLevel, 'normal');
    expect(trip.departureStopId, isNotNull);
    final copy = Trip.fromJson(trip.toJson());
    expect(copy.departsAt, trip.departsAt);
    expect(copy.entityId, trip.entityId);
  });

  test('paradas del itinerario en orden', () {
    final links = fixture('itinerary_stops').resources.map(ItineraryStop.from).toList();
    expect(links.map((l) => l.stop!.landmark), ['Empresa', 'Parque', 'Hospital']);
    expect(links.first.stop!.address, 'Empresa, Calle 1 entre A y B');
    final itinerary = Itinerary.from(fixture('itinerary').resource);
    expect(itinerary.entityId, '1');
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
    final lucia = passengers.single;
    expect(lucia.boarded, isTrue);
    expect(lucia.expected, isTrue);
    expect(lucia.boardingMethod, 'self');
    expect(lucia.eligibleChildren, 1);
    expect(lucia.boardedChildIds, isEmpty);
    expect(lucia.outsider, isNull);
    expect(lucia.worker.fullName, 'Lucía María Pérez García');
    expect(lucia.tripBoardingId, isNotNull);
  });

  test('solicitudes: Entidad, itinerario y rol', () {
    final applications = fixture('applications').resources.map(Application.from).toList();
    expect(applications.map((a) => a.type).toSet(), {ApplicationType.entityMembership, ApplicationType.itineraryMembership, ApplicationType.role});
    final role = applications.firstWhere((a) => a.type == ApplicationType.role);
    expect(role.isPending, isTrue);
    expect(role.subject, 'Chofer');
    expect(role.entityAbbreviation, 'PRUEBA');
    expect(role.canResolve, isFalse);
    final itinerary = applications.firstWhere((a) => a.type == ApplicationType.itineraryMembership);
    expect(itinerary.status, ApplicationStatus.approved);
    expect(itinerary.subject, 'Ruta Este • Parque');
  });

  test('hijo por carné, con quién lo declaró; ausencias; roles', () {
    final child = Child.from(fixture('children').resource);
    expect(child.fullName, 'Pepito Juan Pérez García');
    expect(child.birthDate, '2018-03-05');
    expect(child.sex, 'M');
    expect(child.eligibleUntil, '2034-08-31');
    expect(child.travels, isTrue);
    expect(child.identityCard, '18030564140');
    expect(child.parents.single.fullName, 'Lucía María Pérez García');
    expect(IdentityCard.birthDate(child.identityCard), DateTime(2018, 3, 5));
    expect(IdentityCard.sex(child.identityCard), 'M');

    final absence = Absence.from(fixture('absences').resource);
    expect(absence.indefinite, isFalse);
    expect(absence.note, 'Vacaciones');
    expect(absence.absenceTypeName, isNotEmpty);
    expect(absence.covers(absence.start), isTrue);

    final roles = fixture('roles').resources.map(Role.from).toList();
    expect(roles.first.isAdministrator, isTrue);
    expect(roles.first.editable, isFalse);
    final driver = roles.firstWhere((r) => r.name == 'Chofer');
    expect(driver.requestable, isTrue);
    expect(driver.permissions.map((p) => p.operation), contains(Op.trackingDrive));
    expect(roles.firstWhere((r) => r.name == 'Jefe de itinerario').itineraryScoped, isTrue);
    expect(roles.where((r) => r.isDefault).single.name, 'Trabajador');

    final held = fixture('worker_roles').resources.map(HeldRole.from).toList();
    expect(held.map((r) => r.name), containsAll(['Trabajador', 'Jefe de Transporte', 'Jefe de itinerario']));
    expect(held.firstWhere((r) => r.name == 'Jefe de itinerario').itineraryName, 'Ruta Este');
  });

  test('registro: estado, usuario y contraseña propuestos, registro por el Administrador', () {
    expect(fixture('registration_status').resource.boolean('adminExists'), isFalse);
    expect(fixture('username_suggestion').resource.string('username'), 'ana');
    expect(fixture('password_suggestion').resource.string('password'), isNotEmpty);
    final registered = fixture('worker_registered').resource;
    expect(registered.meta['accountCreated'], isTrue);
    expect(registered.meta['username'], 'carlos');
    expect(registered.meta['password'], isNotEmpty);
    expect(Worker.from(registered).roles.single.name, 'Trabajador');
  });

  test('avisos, mensajes y conversaciones dirigidas a un rol', () {
    expect(fixture('notices').resources.map(Notice.from).first.title, isNotEmpty);
    final message = Message.from(fixture('trip_messages').resource);
    expect(message.authorName, 'Lucía Pérez');
    expect(message.authorId, isNotNull);
    final conversation = Conversation.from(fixture('conversations').resource);
    expect(conversation.recipient, 'role');
    expect(conversation.topicName, 'Reportar un problema');
    expect(conversation.roleName, 'Jefe de itinerario');
    expect(conversation.recipientLabel, 'Jefe de itinerario');
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
  });

  test('vehículo y trabajadores (pertenencias)', () {
    final vehicle = Vehicle.from(fixture('vehicle').resource);
    expect(vehicle.totalCapacity, 1);
    expect(vehicle.vehicleType?.name, 'Guagua');
    expect(vehicle.driverId, '3');
    final workers = fixture('workers').resources.map(Worker.from).toList();
    expect(workers, hasLength(3), reason: 'la Administradora no pertenece a la Entidad');
    expect(workers.every((w) => w.entity?.abbreviation == 'PRUEBA'), isTrue);
    expect(workers.firstWhere((w) => w.firstName == 'Teresa').roles.map((r) => r.name), contains('Jefe de Transporte'));
    expect(workers.firstWhere((w) => w.firstName == 'Carlos').roles.map((r) => r.name), contains('Chofer'));
    expect(workers.firstWhere((w) => w.firstName == 'Lucía').identityCard, '90052002130', reason: 'el Administrador ve el carné');
    expect(Entity.from(fixture('entity_lookup').resource).name, 'Empresa de prueba');
  });
}
