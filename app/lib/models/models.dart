/// Modelos de la app, construidos a partir de recursos JSON:API.
library;

import '../core/json_api.dart';

class Rank {
  final String id;
  final String name;
  final int sortOrder;
  final String? iconUrl;
  final String? description;

  Rank({required this.id, required this.name, this.sortOrder = 0, this.iconUrl, this.description});

  factory Rank.from(Resource r) =>
      Rank(id: r.id, name: r.string('name') ?? '', sortOrder: r.integer('sortOrder') ?? 0, iconUrl: r.string('iconUrl'), description: r.string('description'));
}

/// Los cuatro nombres de una persona (cuentas e hijos).
class PersonName {
  final String firstName;
  final String middleName;
  final String firstSurname;
  final String secondSurname;

  const PersonName({this.firstName = '', this.middleName = '', this.firstSurname = '', this.secondSurname = ''});

  factory PersonName.from(Resource? r) => PersonName(
        firstName: r?.string('firstName') ?? '',
        middleName: r?.string('middleName') ?? '',
        firstSurname: r?.string('firstSurname') ?? '',
        secondSurname: r?.string('secondSurname') ?? '',
      );

  String get full => [firstName, middleName, firstSurname, secondSurname].where((part) => part.isNotEmpty).join(' ');

  /// Primer nombre y primer apellido, para listas y chats.
  String get short => [firstName, firstSurname].where((part) => part.isNotEmpty).join(' ');

  String get initials => '${firstName.isEmpty ? '' : firstName[0]}${firstSurname.isEmpty ? '' : firstSurname[0]}'.toUpperCase();
}

/// Entidad: empresa que usa la app. Se muestra por su abreviatura.
class Entity {
  final String id;
  final String abbreviation;
  final String name;
  final String? number;
  final String? description;
  final String? observation;
  final bool active;

  Entity({required this.id, required this.abbreviation, required this.name, this.number, this.description, this.observation, this.active = true});

  factory Entity.from(Resource r) => Entity(
        id: r.id,
        abbreviation: r.string('abbreviation') ?? '',
        name: r.string('name') ?? '',
        number: r.string('number'),
        description: r.string('description'),
        observation: r.string('observation'),
        active: r.attributes['active'] != false,
      );
}

class Roles {
  final bool isTransportChief;
  final String? driverId;
  final List<String> chiefOfItineraries;

  const Roles({this.isTransportChief = false, this.driverId, this.chiefOfItineraries = const []});

  factory Roles.from(Map<String, dynamic>? json) => Roles(
        isTransportChief: json?['isTransportChief'] == true,
        driverId: json?['driverId']?.toString(),
        chiefOfItineraries: ((json?['chiefOfItineraries'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  bool get isDriver => driverId != null;

  bool get isItineraryChief => chiefOfItineraries.isNotEmpty;
}

/// Trabajador de una Entidad. Los nombres vienen de su cuenta.
class Worker {
  final String id;
  final String? userId;
  final PersonName name;
  final String sex;
  final String? photoUrl;
  final bool active;
  final int? pass;
  final bool activated;
  final String? entityId;
  final String? rankId;
  final String? itineraryId;
  final String? stopId;
  final int childrenCount;
  final Roles roles;
  final Rank? rank;
  final Entity? entity;

  Worker({
    required this.id,
    this.userId,
    this.name = const PersonName(),
    required this.sex,
    this.photoUrl,
    this.active = true,
    this.pass,
    this.activated = true,
    this.entityId,
    this.rankId,
    this.itineraryId,
    this.stopId,
    this.childrenCount = 0,
    this.roles = const Roles(),
    this.rank,
    this.entity,
  });

  factory Worker.from(Resource r) {
    final rank = r.related('rank');
    final entity = r.related('entity');
    return Worker(
      id: r.id,
      userId: r.relId('user')?.id,
      name: PersonName.from(r),
      sex: r.string('sex') ?? 'M',
      photoUrl: r.string('photoUrl'),
      active: r.attributes['active'] != false,
      pass: r.integer('pass'),
      activated: r.attributes['activated'] != false,
      entityId: r.relId('entity')?.id,
      rankId: r.relId('rank')?.id,
      itineraryId: r.relId('itinerary')?.id,
      stopId: r.relId('stop')?.id,
      childrenCount: (r.meta['childrenCount'] as num?)?.toInt() ?? 0,
      roles: Roles.from(r.meta['roles'] as Map<String, dynamic>?),
      rank: rank == null ? null : Rank.from(rank),
      entity: entity == null ? null : Entity.from(entity),
    );
  }

  String get fullName => name.full;

  String get firstName => name.firstName;

  String get initials => name.initials;
}

/// Cuenta de la app (recurso "users").
class Account {
  final String id;
  final String? username;
  final PersonName name;
  final String? photoUrl;
  final bool isAdmin;
  final bool active;
  final bool mustChangePassword;
  final bool currentPasswordRequired;
  final DateTime? passwordExpiresAt;
  final String? workerId;

  Account({
    required this.id,
    this.username,
    this.name = const PersonName(),
    this.photoUrl,
    this.isAdmin = false,
    this.active = true,
    this.mustChangePassword = false,
    this.currentPasswordRequired = true,
    this.passwordExpiresAt,
    this.workerId,
  });

  factory Account.from(Resource r) => Account(
        id: r.id,
        username: r.string('username'),
        name: PersonName.from(r),
        photoUrl: r.string('photoUrl'),
        isAdmin: r.boolean('isAdmin'),
        active: r.attributes['active'] != false,
        mustChangePassword: r.boolean('mustChangePassword'),
        currentPasswordRequired: r.attributes['currentPasswordRequired'] != false,
        passwordExpiresAt: r.date('passwordExpiresAt'),
        workerId: r.relId('worker')?.id,
      );

  String get fullName => name.full;
}

/// El usuario de la sesión: su cuenta y, si pertenece a una Entidad, su trabajador.
///
/// El Administrador no es trabajador: ve y hace todo, en todas las Entidades.
class Me {
  final Account account;
  final Worker? worker;

  Me(this.account, this.worker);

  factory Me.from(Resource r) {
    final worker = r.related('worker');
    return Me(Account.from(r), worker == null ? null : Worker.from(worker));
  }

  /// Id del trabajador ('' para el Administrador, que no lo es).
  String get id => worker?.id ?? '';

  String get userId => account.id;

  bool get hasWorker => worker != null;

  bool get isAdmin => account.isAdmin;

  /// Tiene que unirse a una Entidad antes de usar la app.
  bool get needsEntity => !isAdmin && worker == null;

  String? get username => account.username;

  String get fullName => account.fullName;

  String get firstName => account.name.firstName;

  PersonName get name => account.name;

  String? get photoUrl => account.photoUrl;

  bool get mustChangePassword => account.mustChangePassword;

  String? get entityId => worker?.entityId;

  Entity? get entity => worker?.entity;

  int? get pass => worker?.pass;

  String? get sex => worker?.sex;

  String? get itineraryId => worker?.itineraryId;

  String? get stopId => worker?.stopId;

  Rank? get rank => worker?.rank;

  String? get rankId => worker?.rankId;

  int get childrenCount => worker?.childrenCount ?? 0;

  Roles get roles => worker?.roles ?? const Roles();

  bool get managesTransport => isAdmin || roles.isTransportChief;

  /// El Administrador cuenta como Jefe de todos los itinerarios, y el Jefe de
  /// Transporte como Jefe de los de su Entidad (el servidor solo le muestra esos).
  bool isChiefOf(String? itineraryId) => itineraryId != null && (managesTransport || roles.chiefOfItineraries.contains(itineraryId));

  /// Puede planificar viajes de ese itinerario.
  bool canPlan(String? itineraryId) => isChiefOf(itineraryId);

  /// Puede planificar viajes de algún itinerario.
  bool get plansTrips => managesTransport || roles.isItineraryChief;
}

class Stop {
  final String id;
  final String landmark;
  final String street;
  final String? crossStreet1;
  final String? crossStreet2;
  final double latitude;
  final double longitude;
  final String address;

  Stop({
    required this.id,
    required this.landmark,
    required this.street,
    this.crossStreet1,
    this.crossStreet2,
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  factory Stop.from(Resource r) => Stop(
        id: r.id,
        landmark: r.string('landmark') ?? '',
        street: r.string('street') ?? '',
        crossStreet1: r.string('crossStreet1'),
        crossStreet2: r.string('crossStreet2'),
        latitude: (r.attributes['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (r.attributes['longitude'] as num?)?.toDouble() ?? 0,
        address: r.string('address') ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'landmark': landmark, 'street': street, 'crossStreet1': crossStreet1, 'crossStreet2': crossStreet2,
        'latitude': latitude, 'longitude': longitude, 'address': address,
      };

  factory Stop.fromJson(Map<String, dynamic> json) => Stop(
        id: json['id'] as String,
        landmark: json['landmark'] as String,
        street: json['street'] as String,
        crossStreet1: json['crossStreet1'] as String?,
        crossStreet2: json['crossStreet2'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String,
      );
}

class Itinerary {
  final String id;
  final String name;
  final String? description;
  final String? observation;
  final List<String> stopIds;
  final String? departureStopId;
  final String? returnStopId;
  final int memberCount;

  Itinerary({
    required this.id,
    required this.name,
    this.description,
    this.observation,
    this.stopIds = const [],
    this.departureStopId,
    this.returnStopId,
    this.memberCount = 0,
  });

  factory Itinerary.from(Resource r) => Itinerary(
        id: r.id,
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        stopIds: ((r.meta['stopIds'] as List?) ?? const []).map((e) => e.toString()).toList(),
        departureStopId: (r.meta['departurePoint'] as Map?)?['id']?.toString(),
        returnStopId: (r.meta['returnPoint'] as Map?)?['id']?.toString(),
        memberCount: (r.meta['memberCount'] as num?)?.toInt() ?? 0,
      );
}

class ItineraryStop {
  final String id;
  final int position;
  final String itineraryId;
  final String stopId;
  final Stop? stop;

  ItineraryStop({required this.id, required this.position, required this.itineraryId, required this.stopId, this.stop});

  factory ItineraryStop.from(Resource r) {
    final stop = r.related('stop');
    return ItineraryStop(
      id: r.id,
      position: r.integer('position') ?? 0,
      itineraryId: r.relId('itinerary')!.id,
      stopId: r.relId('stop')!.id,
      stop: stop == null ? null : Stop.from(stop),
    );
  }
}

class Named {
  final String id;
  final String name;
  final String? description;
  final String? observation;
  final Map<String, dynamic> extra;

  Named({required this.id, required this.name, this.description, this.observation, this.extra = const {}});

  factory Named.from(Resource r) => Named(
        id: r.id,
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        extra: r.attributes,
      );
}

class Vehicle {
  final String id;
  final String plate;
  final int seats;
  final int standingCapacity;
  final int totalCapacity;
  final String? vehicleTypeId;
  final String? driverId;
  final Named? vehicleType;

  Vehicle({
    required this.id,
    required this.plate,
    required this.seats,
    required this.standingCapacity,
    required this.totalCapacity,
    this.vehicleTypeId,
    this.driverId,
    this.vehicleType,
  });

  factory Vehicle.from(Resource r) {
    final type = r.related('vehicleType');
    return Vehicle(
      id: r.id,
      plate: r.string('plate') ?? '',
      seats: r.integer('seats') ?? 0,
      standingCapacity: r.integer('standingCapacity') ?? 0,
      totalCapacity: (r.meta['totalCapacity'] as num?)?.toInt() ?? 0,
      vehicleTypeId: r.relId('vehicleType')?.id,
      driverId: r.relId('driver')?.id,
      vehicleType: type == null ? null : Named.from(type),
    );
  }
}

class TripStatus {
  static const unconfirmed = 'unconfirmed';
  static const confirmed = 'confirmed';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static String label(String status) => const {
        unconfirmed: 'No confirmado',
        confirmed: 'Confirmado',
        completed: 'Realizado',
        cancelled: 'Cancelado',
      }[status] ?? status;
}

class Trip {
  final String id;
  final DateTime departsAt;
  final DateTime returnsAt;
  final String status;
  final DateTime? updatedAt;
  final String itineraryId;
  final String vehicleId;
  final String driverId;
  final int expectedPassengers;
  final int expectedChildren;
  final int seats;
  final int totalCapacity;

  /// normal, saturated (van de pie) u overloaded (no caben).
  final String occupancyLevel;
  final bool needsReassignment;
  final String? departureStopId;
  final String? returnStopId;

  // Datos incluidos (para avisos y pantallas)
  final String? itineraryName;
  final String? vehiclePlate;
  final String? vehicleTypeName;
  final String? driverName;
  final String? driverWorkerId;

  Trip({
    required this.id,
    required this.departsAt,
    required this.returnsAt,
    required this.status,
    this.updatedAt,
    required this.itineraryId,
    required this.vehicleId,
    required this.driverId,
    this.expectedPassengers = 0,
    this.expectedChildren = 0,
    this.seats = 0,
    this.totalCapacity = 0,
    this.occupancyLevel = 'normal',
    this.needsReassignment = false,
    this.departureStopId,
    this.returnStopId,
    this.itineraryName,
    this.vehiclePlate,
    this.vehicleTypeName,
    this.driverName,
    this.driverWorkerId,
  });

  factory Trip.from(Resource r) {
    final itinerary = r.related('itinerary');
    final vehicle = r.related('vehicle');
    final vehicleType = vehicle?.related('vehicleType');
    final driver = r.related('driver');
    final driverWorker = driver?.related('worker');
    return Trip(
      id: r.id,
      departsAt: r.date('departsAt')!,
      returnsAt: r.date('returnsAt')!,
      status: r.string('status') ?? TripStatus.unconfirmed,
      updatedAt: r.date('updatedAt'),
      itineraryId: r.relId('itinerary')!.id,
      vehicleId: r.relId('vehicle')!.id,
      driverId: r.relId('driver')!.id,
      expectedPassengers: (r.meta['expectedPassengers'] as num?)?.toInt() ?? 0,
      expectedChildren: (r.meta['expectedChildren'] as num?)?.toInt() ?? 0,
      seats: (r.meta['seats'] as num?)?.toInt() ?? 0,
      totalCapacity: (r.meta['totalCapacity'] as num?)?.toInt() ?? 0,
      occupancyLevel: r.meta['occupancyLevel']?.toString() ?? (r.meta['overloaded'] == true ? 'overloaded' : 'normal'),
      needsReassignment: r.meta['needsReassignment'] == true,
      departureStopId: (r.meta['departurePoint'] as Map?)?['id']?.toString(),
      returnStopId: (r.meta['returnPoint'] as Map?)?['id']?.toString(),
      itineraryName: itinerary?.string('name'),
      vehiclePlate: vehicle?.string('plate'),
      vehicleTypeName: vehicleType?.string('name'),
      driverName: driverWorker == null ? null : PersonName.from(driverWorker).short,
      driverWorkerId: driver?.relId('worker')?.id,
    );
  }

  bool get isConfirmed => status == TripStatus.confirmed;

  bool get overloaded => occupancyLevel == 'overloaded';

  bool get saturated => occupancyLevel == 'saturated';

  Map<String, dynamic> toJson() => {
        'id': id, 'departsAt': departsAt.toIso8601String(), 'returnsAt': returnsAt.toIso8601String(), 'status': status,
        'updatedAt': updatedAt?.toIso8601String(), 'itineraryId': itineraryId, 'vehicleId': vehicleId, 'driverId': driverId,
        'expectedPassengers': expectedPassengers, 'expectedChildren': expectedChildren, 'seats': seats, 'totalCapacity': totalCapacity,
        'occupancyLevel': occupancyLevel, 'needsReassignment': needsReassignment, 'departureStopId': departureStopId,
        'returnStopId': returnStopId, 'itineraryName': itineraryName, 'vehiclePlate': vehiclePlate,
        'vehicleTypeName': vehicleTypeName, 'driverName': driverName, 'driverWorkerId': driverWorkerId,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        departsAt: DateTime.parse(j['departsAt'] as String),
        returnsAt: DateTime.parse(j['returnsAt'] as String),
        status: j['status'] as String,
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
        itineraryId: j['itineraryId'] as String,
        vehicleId: j['vehicleId'] as String,
        driverId: j['driverId'] as String,
        expectedPassengers: j['expectedPassengers'] as int? ?? 0,
        expectedChildren: j['expectedChildren'] as int? ?? 0,
        seats: j['seats'] as int? ?? 0,
        totalCapacity: j['totalCapacity'] as int? ?? 0,
        occupancyLevel: j['occupancyLevel'] as String? ?? (j['overloaded'] == true ? 'overloaded' : 'normal'),
        needsReassignment: j['needsReassignment'] == true,
        departureStopId: j['departureStopId'] as String?,
        returnStopId: j['returnStopId'] as String?,
        itineraryName: j['itineraryName'] as String?,
        vehiclePlate: j['vehiclePlate'] as String?,
        vehicleTypeName: j['vehicleTypeName'] as String?,
        driverName: j['driverName'] as String?,
        driverWorkerId: j['driverWorkerId'] as String?,
      );
}

class TripLeg {
  final String id;
  final String tripId;
  final String direction;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final double? latitude;
  final double? longitude;
  final DateTime? positionAt;
  final int activeSensors;
  final List<StopPass> stopPasses;

  TripLeg({
    required this.id,
    required this.tripId,
    required this.direction,
    required this.startedAt,
    this.endedAt,
    this.endReason,
    this.latitude,
    this.longitude,
    this.positionAt,
    this.activeSensors = 0,
    this.stopPasses = const [],
  });

  factory TripLeg.from(Resource r) {
    final position = r.meta['currentPosition'] as Map?;
    return TripLeg(
      id: r.id,
      tripId: r.relId('trip')!.id,
      direction: r.string('direction')!,
      startedAt: r.date('startedAt')!,
      endedAt: r.date('endedAt'),
      endReason: r.string('endReason'),
      latitude: (position?['latitude'] as num?)?.toDouble(),
      longitude: (position?['longitude'] as num?)?.toDouble(),
      positionAt: position?['at'] == null ? null : DateTime.tryParse(position!['at'] as String)?.toLocal(),
      activeSensors: (r.meta['activeSensors'] as num?)?.toInt() ?? 0,
      stopPasses: ((r.meta['stopPasses'] as List?) ?? const [])
          .map((p) => StopPass(stopId: '${(p as Map)['stopId']}', passedAt: DateTime.parse(p['passedAt'] as String).toLocal()))
          .toList(),
    );
  }

  bool get isActive => endedAt == null;

  bool get isReturn => direction == 'return';

  String get directionLabel => isReturn ? 'Regreso' : 'Salida';
}

class StopPass {
  final String stopId;
  final DateTime passedAt;

  StopPass({required this.stopId, required this.passedAt});
}

class Passenger {
  final Worker worker;
  final String stopId;
  final int position;
  final int eligibleChildren;
  final bool boarded;
  final int? boardedChildren;
  final String? boardingMethod;

  Passenger({
    required this.worker,
    required this.stopId,
    required this.position,
    required this.eligibleChildren,
    required this.boarded,
    this.boardedChildren,
    this.boardingMethod,
  });

  factory Passenger.from(Resource r) => Passenger(
        worker: Worker.from(r.related('worker')!),
        stopId: r.relId('stop')!.id,
        position: r.integer('position') ?? 0,
        eligibleChildren: r.integer('eligibleChildren') ?? 0,
        boarded: r.boolean('boarded'),
        boardedChildren: r.integer('boardedChildren'),
        boardingMethod: r.string('boardingMethod'),
      );
}

class ApplicationType {
  static const itineraryMembership = 'itinerary_membership';
  static const itineraryChief = 'itinerary_chief';
  static const driver = 'driver';
  static const transportChief = 'transport_chief';
  static const childAddition = 'child_addition';
  static const childRemoval = 'child_removal';
  static const absence = 'absence';
  static const itineraryLeave = 'itinerary_leave';
  static const itineraryChiefLeave = 'itinerary_chief_leave';
  static const driverLeave = 'driver_leave';
  static const transportChiefLeave = 'transport_chief_leave';
  static const itineraryRemoval = 'itinerary_removal';

  static String label(String type) => const {
        itineraryMembership: 'Itinerario y parada',
        itineraryChief: 'Jefe de itinerario',
        driver: 'Chofer',
        transportChief: 'Jefe de Transporte',
        childAddition: 'Declarar hijo',
        childRemoval: 'Quitar hijo',
        absence: 'Ausencia temporal',
        itineraryLeave: 'Baja del itinerario',
        itineraryChiefLeave: 'Baja como Jefe de itinerario',
        driverLeave: 'Baja como chofer',
        transportChiefLeave: 'Baja como Jefe de Transporte',
        itineraryRemoval: 'Baja automática por inactividad',
      }[type] ?? type;

  static String statusLabel(String status) => const {
        'pending': 'Pendiente',
        'approved': 'Aprobada',
        'rejected': 'Rechazada',
        'cancelled': 'Cancelada',
      }[status] ?? status;
}

class Application {
  final String id;
  final String type;
  final String status;
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final String workerId;
  final Worker? worker;
  final String? resolverName;
  final String? itineraryName;
  final String? stopName;
  final String? childName;
  final bool possibleDuplicate;
  final bool assigned;
  final String? absenceTypeName;
  final String? startsOn;
  final String? endsOn;
  final String? observation;

  Application({
    required this.id,
    required this.type,
    required this.status,
    this.resolutionNote,
    this.resolvedAt,
    required this.createdAt,
    required this.workerId,
    this.worker,
    this.resolverName,
    this.itineraryName,
    this.stopName,
    this.childName,
    this.possibleDuplicate = false,
    this.assigned = false,
    this.absenceTypeName,
    this.startsOn,
    this.endsOn,
    this.observation,
  });

  factory Application.from(Resource r) {
    final worker = r.related('worker');
    final resolver = r.related('resolvedBy');
    return Application(
      id: r.id,
      type: r.string('type')!,
      status: r.string('status')!,
      resolutionNote: r.string('resolutionNote'),
      resolvedAt: r.date('resolvedAt'),
      createdAt: r.date('createdAt')!,
      workerId: r.relId('worker')!.id,
      worker: worker == null ? null : Worker.from(worker),
      resolverName: resolver == null ? null : PersonName.from(resolver).short,
      itineraryName: r.related('itinerary')?.string('name'),
      stopName: r.related('stop')?.string('landmark'),
      childName: r.string('childFullName'),
      possibleDuplicate: r.boolean('possibleDuplicate'),
      assigned: r.boolean('assigned'),
      absenceTypeName: r.related('absenceType')?.string('name'),
      startsOn: r.string('startsOn'),
      endsOn: r.string('endsOn'),
      observation: r.string('observation'),
    );
  }

  bool get isPending => status == 'pending';

  String get summary {
    final parts = <String>[
      ?itineraryName,
      ?stopName,
      ?childName,
      ?absenceTypeName,
      if (startsOn != null) '$startsOn → $endsOn',
    ];
    return parts.join(' · ');
  }
}

class Child {
  final String id;
  final PersonName name;
  final String? birthDate;
  final bool declared;
  final bool eligible;
  final String? eligibleUntil;

  Child({required this.id, this.name = const PersonName(), this.birthDate, this.declared = false, this.eligible = false, this.eligibleUntil});

  factory Child.from(Resource r) => Child(
        id: r.id,
        name: PersonName.from(r),
        birthDate: r.string('birthDate'),
        declared: r.meta['declared'] == true,
        eligible: r.meta['eligible'] == true,
        eligibleUntil: r.meta['eligibleUntil']?.toString(),
      );

  String get fullName => name.full;
}

class Notice {
  final String id;
  final String type;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? applicationId;
  final String? tripId;
  final String? accessRecoveryId;

  Notice({required this.id, required this.type, this.readAt, required this.createdAt, this.applicationId, this.tripId, this.accessRecoveryId});

  factory Notice.from(Resource r) => Notice(
        id: r.id,
        type: r.string('type')!,
        readAt: r.date('readAt'),
        createdAt: r.date('createdAt')!,
        applicationId: r.relId('application')?.id,
        tripId: r.relId('trip')?.id,
        accessRecoveryId: r.relId('accessRecovery')?.id,
      );

  String get title => const {
        'application_received': 'Hay una solicitud nueva para resolver',
        'application_resolved': 'Se resolvió una de tus solicitudes',
        'resignation': 'Alguien a tu cargo se dio de baja',
        'inactivity_warning': 'Vas a perder tu plaza por inactividad',
        'inactivity_removal': 'Baja automática por inactividad',
        'trip_needs_reassignment': 'Un viaje se quedó sin chofer',
        'role_assigned': 'Un superior te asignó algo nuevo',
        'role_removed': 'Un superior te quitó un rol o tu itinerario',
        'access_recovery_requested': 'Alguien no puede entrar y pide ayuda',
        'password_expiring': 'Tu contraseña caduca pronto',
      }[type] ?? type;
}

class Message {
  final String id;
  final String body;
  final DateTime createdAt;

  /// Cuenta que lo escribió; null = quien abrió la conversación sin cuenta.
  final String? authorId;
  final String? authorName;

  Message({required this.id, required this.body, required this.createdAt, this.authorId, this.authorName});

  factory Message.from(Resource r) {
    final author = r.related('author');
    return Message(
      id: r.id,
      body: r.string('body') ?? '',
      createdAt: r.date('createdAt')!,
      authorId: r.relId('author')?.id,
      authorName: author == null ? null : PersonName.from(author).short,
    );
  }
}

class Conversation {
  final String id;
  final String recipient;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final int messageCount;
  final String? topicName;
  final String? openedById;
  final String? openedByName;
  final bool guest;
  final bool closed;
  final String? guestName;
  final String? guestPhone;
  final String? installationId;

  Conversation({
    required this.id,
    required this.recipient,
    required this.createdAt,
    this.lastMessageAt,
    this.messageCount = 0,
    this.topicName,
    this.openedById,
    this.openedByName,
    this.guest = false,
    this.closed = false,
    this.guestName,
    this.guestPhone,
    this.installationId,
  });

  factory Conversation.from(Resource r) {
    final opener = r.related('openedBy');
    return Conversation(
      id: r.id,
      recipient: r.string('recipient') ?? '',
      createdAt: r.date('createdAt')!,
      lastMessageAt: r.date('lastMessageAt'),
      messageCount: (r.meta['messageCount'] as num?)?.toInt() ?? 0,
      topicName: r.related('topic')?.string('name'),
      openedById: r.relId('openedBy')?.id,
      openedByName: opener == null ? null : PersonName.from(opener).full,
      guest: r.boolean('guest'),
      closed: r.boolean('closed'),
      guestName: r.string('guestName'),
      guestPhone: r.string('guestPhone'),
      installationId: r.relId('installation')?.id,
    );
  }

  static String recipientLabel(String recipient) => const {
        'itinerary_chiefs': 'Jefes de mi itinerario',
        'transport_chiefs': 'Jefes de Transporte',
        'developer': 'Desarrollador',
      }[recipient] ?? recipient;
}

class SettingDefinition {
  final String key;
  final String name;
  final String? description;
  final String valueType;
  final String defaultValue;
  final int? minValue;
  final int? maxValue;
  final String? minSetting;
  final String? level;
  final bool userOverridable;
  final Map<String, String> options;

  SettingDefinition({
    required this.key,
    required this.name,
    this.description,
    required this.valueType,
    required this.defaultValue,
    this.minValue,
    this.maxValue,
    this.minSetting,
    this.level,
    this.userOverridable = false,
    this.options = const {},
  });

  factory SettingDefinition.from(Resource r) => SettingDefinition(
        key: r.string('key')!,
        name: r.string('name') ?? '',
        description: r.string('description'),
        valueType: r.string('valueType')!,
        defaultValue: r.string('defaultValue') ?? '',
        minValue: r.integer('minValue'),
        maxValue: r.integer('maxValue'),
        minSetting: r.string('minSetting'),
        level: r.string('level'),
        userOverridable: r.boolean('userOverridable'),
        options: {for (final o in (r.attributes['options'] as List? ?? const [])) '${(o as Map)['value']}': '${o['name']}'},
      );
}
