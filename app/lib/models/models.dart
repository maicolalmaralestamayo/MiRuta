/// Modelos de la app, construidos a partir de recursos JSON:API.
///
/// La persona, sus hijos y su carné están en person.dart; pertenencias,
/// roles y permisos en access.dart; solicitudes y ausencias en requests.dart.
library;

import '../core/json_api.dart';
import 'access.dart';
import 'person.dart';

export 'access.dart';
export 'person.dart';
export 'requests.dart';

/// Pertenencia de una persona a una Entidad (recurso `workers`), con los
/// datos de la persona. Es lo que se ve en listas de trabajadores, pasajeros
/// y choferes.
class Worker {
  final String id;
  final String? userId;
  final PersonName name;
  final String? sex;
  final String? photoUrl;
  final bool hasPhone;
  final bool active;

  /// Solo si quien consulta puede verlo (workers.view_identity_card).
  final String? identityCard;
  final String? entityId;
  final String? itineraryId;
  final String? stopId;
  final DateTime? itineraryAssignedAt;
  final List<HeldRole> roles;
  final Entity? entity;

  Worker({
    required this.id,
    this.userId,
    this.name = const PersonName(),
    this.sex,
    this.photoUrl,
    this.hasPhone = true,
    this.active = true,
    this.identityCard,
    this.entityId,
    this.itineraryId,
    this.stopId,
    this.itineraryAssignedAt,
    this.roles = const [],
    this.entity,
  });

  factory Worker.from(Resource r) {
    final entity = r.related('entity');
    return Worker(
      id: r.id,
      userId: r.relId('user')?.id,
      name: PersonName.from(r),
      sex: r.string('sex'),
      photoUrl: r.string('photoUrl'),
      hasPhone: r.attributes['hasPhone'] != false,
      active: r.attributes['active'] != false,
      identityCard: r.string('identityCard'),
      entityId: r.relId('entity')?.id,
      itineraryId: r.relId('itinerary')?.id,
      stopId: r.relId('stop')?.id,
      itineraryAssignedAt: r.date('itineraryAssignedAt'),
      roles: [for (final role in (r.meta['roles'] as List? ?? const [])) HeldRole.fromJson(Map<String, dynamic>.from(role as Map))],
      entity: entity == null ? null : Entity.from(entity),
    );
  }

  String get fullName => name.full;

  String get firstName => name.firstName;

  String get initials => name.initials;
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
  final String? imageUrl;

  Stop({
    required this.id,
    required this.landmark,
    required this.street,
    this.crossStreet1,
    this.crossStreet2,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.imageUrl,
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
        imageUrl: r.string('imageUrl'),
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
  final String? entityId;
  final String? imageUrl;

  /// Recorridos de referencia (viaje de ida / de regreso ya realizados) para detectar desvíos.
  final String? referenceOutboundLegId;
  final String? referenceReturnLegId;

  Itinerary({
    required this.id,
    required this.name,
    this.description,
    this.observation,
    this.stopIds = const [],
    this.departureStopId,
    this.returnStopId,
    this.memberCount = 0,
    this.entityId,
    this.imageUrl,
    this.referenceOutboundLegId,
    this.referenceReturnLegId,
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
        entityId: r.relId('entity')?.id,
        imageUrl: r.string('imageUrl'),
        referenceOutboundLegId: r.relId('referenceOutboundLeg')?.id,
        referenceReturnLegId: r.relId('referenceReturnLeg')?.id,
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

  /// Ids de sus relaciones a uno (p. ej. `role` de un motivo de conversación).
  final Map<String, String> relations;

  Named({required this.id, required this.name, this.description, this.observation, this.extra = const {}, this.relations = const {}});

  factory Named.from(Resource r) => Named(
        id: r.id,
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        extra: r.attributes,
        relations: {
          for (final name in r.relationships.keys)
            if (r.relId(name) != null) name: r.relId(name)!.id,
        },
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
  /// Pertenencia (`workers`) del chofer.
  final String driverId;
  final int expectedPassengers;
  final int seats;
  final int totalCapacity;

  /// normal, saturated (van de pie) u overloaded (no caben).
  final String occupancyLevel;
  final bool needsReassignment;
  final String? departureStopId;
  final String? returnStopId;

  /// Atraso (docs/09): sin comenzar pasada la hora más la tolerancia, y minutos de atraso.
  final bool outboundDelayed;
  final bool returnDelayed;
  final int? outboundDelayMinutes;
  final int? returnDelayMinutes;

  // Datos incluidos (para avisos y pantallas)
  final String? itineraryName;
  final String? vehiclePlate;
  final String? vehicleTypeName;
  final String? driverName;

  /// Entidad del viaje (la del itinerario, si vino incluido).
  final String? entityId;

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
    this.seats = 0,
    this.totalCapacity = 0,
    this.occupancyLevel = 'normal',
    this.needsReassignment = false,
    this.departureStopId,
    this.returnStopId,
    this.outboundDelayed = false,
    this.returnDelayed = false,
    this.outboundDelayMinutes,
    this.returnDelayMinutes,
    this.itineraryName,
    this.vehiclePlate,
    this.vehicleTypeName,
    this.driverName,
    this.entityId,
  });

  factory Trip.from(Resource r) {
    final itinerary = r.related('itinerary');
    final vehicle = r.related('vehicle');
    final vehicleType = vehicle?.related('vehicleType');
    final driver = r.related('driver');
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
      seats: (r.meta['seats'] as num?)?.toInt() ?? 0,
      totalCapacity: (r.meta['totalCapacity'] as num?)?.toInt() ?? 0,
      occupancyLevel: r.meta['occupancyLevel']?.toString() ?? (r.meta['overloaded'] == true ? 'overloaded' : 'normal'),
      needsReassignment: r.meta['needsReassignment'] == true,
      departureStopId: (r.meta['departurePoint'] as Map?)?['id']?.toString(),
      returnStopId: (r.meta['returnPoint'] as Map?)?['id']?.toString(),
      outboundDelayed: r.boolean('outboundDelayed'),
      returnDelayed: r.boolean('returnDelayed'),
      outboundDelayMinutes: r.integer('outboundDelayMinutes'),
      returnDelayMinutes: r.integer('returnDelayMinutes'),
      itineraryName: itinerary?.string('name'),
      vehiclePlate: vehicle?.string('plate'),
      vehicleTypeName: vehicleType?.string('name'),
      driverName: driver == null ? null : PersonName.from(driver).short,
      entityId: itinerary?.relId('entity')?.id,
    );
  }

  bool get isConfirmed => status == TripStatus.confirmed;

  bool get overloaded => occupancyLevel == 'overloaded';

  bool get saturated => occupancyLevel == 'saturated';

  Map<String, dynamic> toJson() => {
        'id': id, 'departsAt': departsAt.toIso8601String(), 'returnsAt': returnsAt.toIso8601String(), 'status': status,
        'updatedAt': updatedAt?.toIso8601String(), 'itineraryId': itineraryId, 'vehicleId': vehicleId, 'driverId': driverId,
        'expectedPassengers': expectedPassengers, 'seats': seats, 'totalCapacity': totalCapacity,
        'occupancyLevel': occupancyLevel, 'needsReassignment': needsReassignment, 'departureStopId': departureStopId,
        'returnStopId': returnStopId, 'outboundDelayed': outboundDelayed, 'returnDelayed': returnDelayed,
        'outboundDelayMinutes': outboundDelayMinutes, 'returnDelayMinutes': returnDelayMinutes, 'itineraryName': itineraryName, 'vehiclePlate': vehiclePlate,
        'vehicleTypeName': vehicleTypeName, 'driverName': driverName, 'entityId': entityId,
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
        seats: j['seats'] as int? ?? 0,
        totalCapacity: j['totalCapacity'] as int? ?? 0,
        occupancyLevel: j['occupancyLevel'] as String? ?? (j['overloaded'] == true ? 'overloaded' : 'normal'),
        needsReassignment: j['needsReassignment'] == true,
        departureStopId: j['departureStopId'] as String?,
        returnStopId: j['returnStopId'] as String?,
        outboundDelayed: j['outboundDelayed'] == true,
        returnDelayed: j['returnDelayed'] == true,
        outboundDelayMinutes: j['outboundDelayMinutes'] as int?,
        returnDelayMinutes: j['returnDelayMinutes'] as int?,
        itineraryName: j['itineraryName'] as String?,
        vehiclePlate: j['vehiclePlate'] as String?,
        vehicleTypeName: j['vehicleTypeName'] as String?,
        driverName: j['driverName'] as String?,
        entityId: j['entityId'] as String?,
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
  final bool deviating;
  final List<TripIncident> incidents;

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
    this.deviating = false,
    this.incidents = const [],
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
          .map((p) => StopPass(
                stopId: '${(p as Map)['stopId']}',
                passedAt: DateTime.parse(p['passedAt'] as String).toLocal(),
                status: p['status']?.toString() ?? 'stopped',
              ))
          .toList(),
      deviating: r.meta['deviating'] == true,
      incidents: ((r.meta['incidents'] as List?) ?? const []).map((i) => TripIncident.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
    );
  }

  bool get isActive => endedAt == null;

  bool get isReturn => direction == 'return';

  /// "Viaje de ida" o "Viaje de regreso" (docs/09 §9).
  String get directionLabel => directionName(direction);

  static String directionName(String direction) => direction == 'return' ? 'Viaje de regreso' : 'Viaje de ida';

  /// Paradas donde no se detuvo y paradas saltadas.
  int get notStoppedCount => stopPasses.where((p) => p.status == 'not_stopped').length;

  int get skippedCount => stopPasses.where((p) => p.status == 'skipped').length;
}

class StopPass {
  final String stopId;
  final DateTime passedAt;

  /// arrived (está en la parada), stopped, not_stopped (pasó de largo) o skipped (se la saltó).
  final String status;

  StopPass({required this.stopId, required this.passedAt, this.status = 'stopped'});

  bool get skipped => status == 'skipped';

  bool get notStopped => status == 'not_stopped';
}

/// Incidencia del recorrido (docs/09 §8): no se detuvo, se saltó la parada o se desvió.
class TripIncident {
  final String type;
  final String? stopId;
  final double? latitude;
  final double? longitude;
  final int? distanceM;
  final DateTime startedAt;
  final DateTime? endedAt;

  TripIncident({required this.type, this.stopId, this.latitude, this.longitude, this.distanceM, required this.startedAt, this.endedAt});

  factory TripIncident.fromJson(Map<String, dynamic> j) => TripIncident(
        type: j['type'] as String,
        stopId: j['stopId']?.toString(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        distanceM: (j['distanceM'] as num?)?.toInt(),
        startedAt: DateTime.parse(j['startedAt'] as String).toLocal(),
        endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt'] as String).toLocal(),
      );

  String get label => const {'not_stopped': 'No se detuvo', 'skipped': 'Se saltó la parada', 'deviation': 'Se desvió del recorrido'}[type] ?? type;
}

/// Fila de GET /trips/{id}/passengers: esperados por parada y, al final,
/// quienes subieron sin ser esperados (`expected: false`).
class Passenger {
  final Worker worker;
  final String? stopId;
  final int position;
  final bool expected;

  /// Hijos con derecho (informativo; null si no es esperado).
  final int? eligibleChildren;
  final bool boarded;
  final int? boardedChildren;
  final List<String> boardedChildIds;
  final String? boardingMethod;

  /// `itinerary` o `entity` si subió siendo de otro itinerario o Entidad.
  final String? outsider;
  final String? tripBoardingId;

  Passenger({
    required this.worker,
    this.stopId,
    required this.position,
    this.expected = true,
    this.eligibleChildren,
    required this.boarded,
    this.boardedChildren,
    this.boardedChildIds = const [],
    this.boardingMethod,
    this.outsider,
    this.tripBoardingId,
  });

  factory Passenger.from(Resource r) => Passenger(
        worker: Worker.from(r.related('worker')!),
        stopId: r.relId('stop')?.id,
        position: r.integer('position') ?? 0,
        expected: r.attributes['expected'] != false,
        eligibleChildren: r.integer('eligibleChildren'),
        boarded: r.boolean('boarded'),
        boardedChildren: r.integer('boardedChildren'),
        boardedChildIds: ((r.attributes['boardedChildIds'] as List?) ?? const []).map((e) => '$e').toList(),
        boardingMethod: r.string('boardingMethod'),
        outsider: r.string('outsider'),
        tripBoardingId: r.relId('tripBoarding')?.id,
      );
}

class Notice {
  final String id;
  final String type;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? applicationId;
  final String? tripId;
  final String? accessRecoveryId;

  /// Texto concreto que compone el servidor (qué, quién y, si se rechazó, el motivo).
  final String message;

  Notice({required this.id, required this.type, this.readAt, required this.createdAt, this.applicationId, this.tripId, this.accessRecoveryId, this.message = ''});

  factory Notice.from(Resource r) => Notice(
        id: r.id,
        type: r.string('type')!,
        readAt: r.date('readAt'),
        createdAt: r.date('createdAt')!,
        applicationId: r.relId('application')?.id,
        tripId: r.relId('trip')?.id,
        accessRecoveryId: r.relId('accessRecovery')?.id,
        message: r.string('message') ?? '',
      );

  /// Título breve (para la notificación del teléfono).
  String get title => const {
        'application_received': 'Solicitud nueva para resolver',
        'application_resolved': 'Solicitud resuelta',
        'resignation': 'Baja de un trabajador a su cargo',
        'inactivity_warning': 'Aviso de inactividad',
        'inactivity_removal': 'Baja por inactividad',
        'trip_needs_reassignment': 'Viaje sin chofer',
        'role_assigned': 'Rol asignado',
        'role_removed': 'Rol quitado',
        'entity_added': 'Alta en una Entidad',
        'entity_removed': 'Baja de una Entidad',
        'itinerary_assigned': 'Itinerario y parada asignados',
        'itinerary_removed': 'Baja del itinerario',
        'access_recovery_requested': 'Solicitud «Olvidé algo»',
        'password_expiring': 'Su contraseña caduca pronto',
        'trip_started': 'Comenzó el viaje',
        'trip_delayed': 'Viaje atrasado',
        'trip_incident': 'Incidencia en el recorrido',
      }[type] ?? type;

  /// Texto del aviso: el del servidor o, si no llega, el título.
  String get text => message.isNotEmpty ? message : title;
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

  /// Rol al que va dirigida (recipient = role).
  final String? roleName;
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
    this.roleName,
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
      roleName: r.related('topic')?.string('roleName'),
      openedById: r.relId('openedBy')?.id,
      openedByName: opener == null ? null : PersonName.from(opener).full,
      guest: r.boolean('guest'),
      closed: r.boolean('closed'),
      guestName: r.string('guestName'),
      guestPhone: r.string('guestPhone'),
      installationId: r.relId('installation')?.id,
    );
  }

  /// A quién va: el rol («Jefe de itinerario») o «Desarrollador».
  String get recipientLabel => recipient == 'developer' ? 'Desarrollador' : (roleName ?? 'Rol');
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
  final String? maxSetting;
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
    this.maxSetting,
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
        maxSetting: r.string('maxSetting'),
        level: r.string('level'),
        userOverridable: r.boolean('userOverridable'),
        options: {for (final o in (r.attributes['options'] as List? ?? const [])) '${(o as Map)['value']}': '${o['name']}'},
      );
}

/// Mapa propio (docs/09, Mapas): de dónde salen las imágenes, límites de Cuba y
/// zona de la Entidad para descargarla.
class MapConfig {
  final String tilesUrl;
  final int minZoom;
  final int maxZoom;
  final int downloadMinZoom;
  final int downloadMaxZoom;
  final GeoBox bounds;
  final GeoBox? area;

  MapConfig({required this.tilesUrl, this.minZoom = 7, this.maxZoom = 17, this.downloadMinZoom = 12, this.downloadMaxZoom = 17, required this.bounds, this.area});

  factory MapConfig.fromJson(Map<String, dynamic> j) => MapConfig(
        tilesUrl: j['tilesUrl'] as String? ?? '/tiles/{z}/{x}/{y}.png',
        minZoom: (j['minZoom'] as num?)?.toInt() ?? 7,
        maxZoom: (j['maxZoom'] as num?)?.toInt() ?? 17,
        downloadMinZoom: (j['downloadMinZoom'] as num?)?.toInt() ?? 12,
        downloadMaxZoom: (j['downloadMaxZoom'] as num?)?.toInt() ?? 17,
        bounds: GeoBox.fromJson(Map<String, dynamic>.from(j['bounds'] as Map)),
        area: j['area'] == null ? null : GeoBox.fromJson(Map<String, dynamic>.from(j['area'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'tilesUrl': tilesUrl, 'minZoom': minZoom, 'maxZoom': maxZoom, 'downloadMinZoom': downloadMinZoom,
        'downloadMaxZoom': downloadMaxZoom, 'bounds': bounds.toJson(), 'area': area?.toJson(),
      };
}

class GeoBox {
  final double south;
  final double west;
  final double north;
  final double east;

  const GeoBox({required this.south, required this.west, required this.north, required this.east});

  factory GeoBox.fromJson(Map<String, dynamic> j) => GeoBox(
        south: (j['south'] as num).toDouble(),
        west: (j['west'] as num).toDouble(),
        north: (j['north'] as num).toDouble(),
        east: (j['east'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'south': south, 'west': west, 'north': north, 'east': east};
}
