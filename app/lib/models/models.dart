/// Modelos de la app (versión 4.0, API de docs/13-api-proxima-version.md).
library;

import '../core/formats.dart';
import '../core/json_api.dart';

String? _str(Object? value) => value?.toString();

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// Nombres y apellidos de una persona o de un hijo.
class PersonName {
  final String firstName;
  final String middleName;
  final String firstSurname;
  final String secondSurname;

  const PersonName({this.firstName = '', this.middleName = '', this.firstSurname = '', this.secondSurname = ''});

  factory PersonName.from(Resource r) => PersonName(
        firstName: r.string('firstName') ?? '',
        middleName: r.string('middleName') ?? '',
        firstSurname: r.string('firstSurname') ?? '',
        secondSurname: r.string('secondSurname') ?? '',
      );

  String get full => [firstName, middleName, firstSurname, secondSurname].where((p) => p.trim().isNotEmpty).join(' ');

  Map<String, dynamic> toAttributes() => {
        'firstName': firstName.trim(),
        'middleName': middleName.trim().isEmpty ? null : middleName.trim(),
        'firstSurname': firstSurname.trim(),
        'secondSurname': secondSurname.trim(),
      };
}

/// Carné de identidad cubano (11 dígitos): de él salen el sexo y la fecha de nacimiento.
class IdentityCard {
  static const length = 11;

  static DateTime? birthDate(String? card, {DateTime? today}) {
    final text = (card ?? '').trim();
    if (!RegExp(r'^\d{11}$').hasMatch(text)) return null;
    final yy = int.parse(text.substring(0, 2));
    final mm = int.parse(text.substring(2, 4));
    final dd = int.parse(text.substring(4, 6));
    final century = int.parse(text[6]);
    final base = century == 9 ? 1800 : (century <= 5 ? 1900 : 2000);
    final year = base + yy;
    final date = DateTime(year, mm, dd);
    if (date.year != year || date.month != mm || date.day != dd) return null;
    final now = today ?? DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) return null;
    return date;
  }

  /// 'M' o 'F', o null si el carné no es válido.
  static String? sex(String? card) {
    if (birthDate(card) == null) return null;
    return int.parse(card!.trim()[9]).isEven ? 'M' : 'F';
  }

  static String? validate(String? card) {
    final text = (card ?? '').trim();
    if (text.isEmpty) return 'Escriba el carné de identidad';
    if (!RegExp(r'^\d{11}$').hasMatch(text)) return 'El carné tiene 11 dígitos';
    if (birthDate(text) == null) return 'El carné no es válido';
    return null;
  }
}

String sexName(String? sex) => switch (sex) { 'M' => 'Masculino', 'F' => 'Femenino', _ => '' };

/// «Masculino • vie. 15-03-85».
String sexAndBirth(String? sex, DateTime? birth) => [sexName(sex), if (birth != null) formatDate(birth)].where((s) => s.isNotEmpty).join(' • ');

/// Rol fijo de la persona (docs/11 §11.30).
enum Role { administrador, jefe, trabajador }

Role roleFrom(String? value) => switch (value) { 'administrador' => Role.administrador, 'jefe' => Role.jefe, _ => Role.trabajador };

String roleName(Role role) => switch (role) {
      Role.administrador => 'Administrador',
      Role.jefe => 'Jefe de itinerario',
      Role.trabajador => 'Trabajador',
    };

/// Uno de sus itinerarios en una Entidad, con su parada (docs/11 §11.58).
/// [id] es el del recurso `worker-itineraries`.
class Placement {
  final String id;
  final String workerId;
  final bool isChief;
  final String entityId;
  final String entityAbbreviation;
  final String itineraryId;
  final String itineraryName;
  final String? itineraryImageUrl;
  final bool itineraryActive;
  final int itineraryWorkerCount;
  final String? stopId;
  final String? stopLandmark;
  final String? stopStreet;
  final String? stopImageUrl;
  final double? stopLatitude;
  final double? stopLongitude;

  /// La persona (en las listas de worker-itineraries).
  final String? userId;
  final String? userName;
  final String? photoUrl;
  final bool active;

  const Placement({
    required this.id,
    this.workerId = '',
    this.isChief = false,
    this.entityId = '',
    this.entityAbbreviation = '',
    required this.itineraryId,
    this.itineraryName = '',
    this.itineraryImageUrl,
    this.itineraryActive = true,
    this.itineraryWorkerCount = 0,
    this.stopId,
    this.stopLandmark,
    this.stopStreet,
    this.stopImageUrl,
    this.stopLatitude,
    this.stopLongitude,
    this.userId,
    this.userName,
    this.photoUrl,
    this.active = true,
  });

  factory Placement.fromJson(Map<String, dynamic> j, {String workerId = '', String entityId = '', String entityAbbreviation = ''}) {
    final itinerary = Map<String, dynamic>.from(j['itinerary'] as Map? ?? const {});
    final stop = j['stop'] is Map ? Map<String, dynamic>.from(j['stop'] as Map) : null;
    return Placement(
      id: '${j['id']}',
      workerId: workerId,
      isChief: j['isChief'] == true,
      entityId: entityId,
      entityAbbreviation: entityAbbreviation,
      itineraryId: '${itinerary['id']}',
      itineraryName: '${itinerary['name'] ?? ''}',
      itineraryImageUrl: _str(itinerary['imageUrl']),
      itineraryActive: itinerary['active'] != false,
      itineraryWorkerCount: _int(itinerary['workerCount']),
      stopId: _str(stop?['id']),
      stopLandmark: _str(stop?['landmark']),
      stopStreet: _str(stop?['street']),
      stopImageUrl: _str(stop?['imageUrl']),
      stopLatitude: (stop?['latitude'] as num?)?.toDouble(),
      stopLongitude: (stop?['longitude'] as num?)?.toDouble(),
    );
  }

  /// La persona en un itinerario (recurso worker-itineraries, con su meta).
  factory Placement.from(Resource r) => Placement(
        id: r.id,
        workerId: r.relId('worker')?.id ?? '',
        isChief: r.boolean('isChief'),
        entityId: _str(r.meta['entityId']) ?? '',
        entityAbbreviation: _str(r.meta['entityAbbreviation']) ?? '',
        itineraryId: r.relId('itinerary')?.id ?? '',
        itineraryName: _str(r.meta['itineraryName']) ?? '',
        stopId: r.relId('stop')?.id,
        stopLandmark: _str(r.meta['stopLandmark']),
        userId: r.relId('user')?.id,
        userName: _str(r.meta['userName']),
        photoUrl: _str(r.meta['photoUrl']),
        active: r.meta['active'] != false,
      );
}

/// Una de sus Entidades con sus itinerarios (meta.memberships de GET me y de
/// GET users/{id}).
class Membership {
  final String workerId;
  final bool active;
  final String entityId;
  final String entityAbbreviation;
  final String entityName;
  final String? entityImageUrl;
  final bool entityActive;
  final int entityWorkerCount;
  final List<Placement> itineraries;

  const Membership({
    required this.workerId,
    this.active = true,
    required this.entityId,
    required this.entityAbbreviation,
    this.entityName = '',
    this.entityImageUrl,
    this.entityActive = true,
    this.entityWorkerCount = 0,
    this.itineraries = const [],
  });

  factory Membership.fromJson(Map<String, dynamic> j) {
    final entity = Map<String, dynamic>.from(j['entity'] as Map? ?? const {});
    final workerId = '${j['workerId']}';
    final entityId = '${entity['id']}';
    final abbreviation = '${entity['abbreviation'] ?? ''}';
    return Membership(
      workerId: workerId,
      active: j['active'] != false,
      entityId: entityId,
      entityAbbreviation: abbreviation,
      entityName: '${entity['name'] ?? ''}',
      entityImageUrl: _str(entity['imageUrl']),
      entityActive: entity['active'] != false,
      entityWorkerCount: _int(entity['workerCount']),
      itineraries: [
        for (final i in (j['itineraries'] as List? ?? const []))
          Placement.fromJson(Map<String, dynamic>.from(i as Map), workerId: workerId, entityId: entityId, entityAbbreviation: abbreviation),
      ],
    );
  }
}

List<Membership> membershipsFrom(Object? raw) => [for (final m in (raw as List? ?? const [])) Membership.fromJson(Map<String, dynamic>.from(m as Map))];

/// La persona que usa la app (GET me).
class Me {
  final String userId;
  final String username;
  final PersonName name;
  final String fullName;
  final String? sex;
  final String? photoUrl;
  final bool isAdmin;
  final String? identityCard;
  final DateTime? birthDate;
  final bool mustChangePassword;
  final bool currentPasswordRequired;
  final DateTime? passwordExpiresAt;
  final Role role;
  final String? chiefItineraryId;
  final List<Membership> memberships;

  const Me({
    required this.userId,
    this.username = '',
    this.name = const PersonName(),
    this.fullName = '',
    this.sex,
    this.photoUrl,
    this.isAdmin = false,
    this.identityCard,
    this.birthDate,
    this.mustChangePassword = false,
    this.currentPasswordRequired = true,
    this.passwordExpiresAt,
    this.role = Role.trabajador,
    this.chiefItineraryId,
    this.memberships = const [],
  });

  factory Me.from(Resource r) => Me(
        userId: r.id,
        username: r.string('username') ?? '',
        name: PersonName.from(r),
        fullName: r.string('fullName') ?? '',
        sex: r.string('sex'),
        photoUrl: r.string('photoUrl'),
        isAdmin: r.boolean('isAdmin'),
        identityCard: r.string('identityCard'),
        birthDate: parseDay(r.string('birthDate')),
        mustChangePassword: r.boolean('mustChangePassword'),
        currentPasswordRequired: r.attributes['currentPasswordRequired'] != false,
        passwordExpiresAt: r.date('passwordExpiresAt'),
        role: roleFrom(r.meta['role']?.toString()),
        chiefItineraryId: _str(r.meta['chiefItineraryId']),
        memberships: membershipsFrom(r.meta['memberships']),
      );

  bool get isChief => role == Role.jefe;

  /// Administrador o Jefe: gestiona (con sus límites).
  bool get manages => isAdmin || chiefItineraryId != null;

  Membership? membershipIn(String? entityId) => memberships.where((m) => m.entityId == entityId).firstOrNull;

  /// Todos sus itinerarios (de todas sus Entidades), con su parada.
  List<Placement> get placements => [for (final m in memberships) ...m.itineraries];

  Placement? placementIn(String? itineraryId) => placements.where((p) => p.itineraryId == itineraryId).firstOrNull;

  Placement? get chiefPlacement => placements.where((p) => p.isChief).firstOrNull;

  bool get hasEntity => memberships.isNotEmpty;

  bool get hasItinerary => placements.isNotEmpty;

  bool get hasStop => placements.any((p) => p.stopId != null);

  /// Puede ver viajes: algún itinerario con parada (el Jefe aunque no tenga parada; el Administrador, todos).
  bool get seesTrips => isAdmin || chiefItineraryId != null || placements.any((p) => p.stopId != null);

  bool isChiefOf(String? itineraryId) => itineraryId != null && chiefItineraryId == itineraryId;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'isAdmin': isAdmin,
        'role': role.name,
        'chiefItineraryId': chiefItineraryId,
        'itineraryIds': [for (final p in placements) p.itineraryId],
        // Donde viaja (con parada): recordatorios y cálculo de su estado.
        'travelItineraryIds': [for (final p in placements) if (p.stopId != null) p.itineraryId],
      };
}

/// Entidad.
class Entity {
  final String id;
  final String abbreviation;
  final String? number;
  final String name;
  final String? description;
  final String? observation;
  final String? imageUrl;
  final bool active;
  final int workerCount;
  final int itineraryCount;
  final int pendingApplications;

  const Entity({required this.id, this.abbreviation = '', this.number, this.name = '', this.description, this.observation, this.imageUrl, this.active = true, this.workerCount = 0, this.itineraryCount = 0, this.pendingApplications = 0});

  factory Entity.from(Resource r) => Entity(
        id: r.id,
        abbreviation: r.string('abbreviation') ?? '',
        number: r.string('number'),
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        imageUrl: r.string('imageUrl'),
        active: r.attributes['active'] != false,
        workerCount: _int(r.meta['workerCount']),
        itineraryCount: _int(r.meta['itineraryCount']),
        pendingApplications: _int(r.meta['pendingApplications']),
      );
}

/// Itinerario.
class Itinerary {
  final String id;
  final String name;
  final String? description;
  final String? observation;
  final String? imageUrl;
  final bool active;
  final String? entityId;
  final String? entityAbbreviation;
  final int stopCount;
  final int workerCount;
  final int pendingApplications;

  const Itinerary({required this.id, this.name = '', this.description, this.observation, this.imageUrl, this.active = true, this.entityId, this.entityAbbreviation, this.stopCount = 0, this.workerCount = 0, this.pendingApplications = 0});

  factory Itinerary.from(Resource r) => Itinerary(
        id: r.id,
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        imageUrl: r.string('imageUrl'),
        active: r.attributes['active'] != false,
        entityId: r.relId('entity')?.id,
        entityAbbreviation: r.related('entity')?.string('abbreviation'),
        stopCount: _int(r.meta['stopCount']),
        workerCount: _int(r.meta['workerCount']),
        pendingApplications: _int(r.meta['pendingApplications']),
      );
}

/// Un itinerario en el que está una parada (meta.itineraries de la parada).
class StopLink {
  final String itineraryStopId;
  final String itineraryId;
  final String name;
  final String? entityId;
  final String? entityAbbreviation;
  final int position;

  const StopLink({required this.itineraryStopId, required this.itineraryId, required this.name, this.entityId, this.entityAbbreviation, required this.position});

  factory StopLink.fromJson(Map<String, dynamic> j) => StopLink(
        itineraryStopId: '${j['itineraryStopId']}',
        itineraryId: '${j['itineraryId']}',
        name: '${j['name'] ?? ''}',
        entityId: _str(j['entityId']),
        entityAbbreviation: _str(j['entityAbbreviation']),
        position: _int(j['position']),
      );
}

/// Parada (compartida entre itinerarios y Entidades).
class Stop {
  final String id;
  final String landmark;
  final String street;
  final String? crossStreet1;
  final String? crossStreet2;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final bool active;
  final List<StopLink> itineraries;
  final int workerCount;

  const Stop({required this.id, this.landmark = '', this.street = '', this.crossStreet1, this.crossStreet2, this.latitude = 0, this.longitude = 0, this.imageUrl, this.active = true, this.itineraries = const [], this.workerCount = 0});

  factory Stop.from(Resource r) => Stop(
        id: r.id,
        landmark: r.string('landmark') ?? '',
        street: r.string('street') ?? '',
        crossStreet1: r.string('crossStreet1'),
        crossStreet2: r.string('crossStreet2'),
        latitude: (r.attributes['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (r.attributes['longitude'] as num?)?.toDouble() ?? 0,
        imageUrl: r.string('imageUrl'),
        active: r.attributes['active'] != false,
        itineraries: [for (final i in (r.meta['itineraries'] as List? ?? const [])) StopLink.fromJson(Map<String, dynamic>.from(i as Map))],
        workerCount: _int(r.meta['workerCount']),
      );

  /// «Calle 23 • entre K y L».
  String get address {
    final cross = [crossStreet1, crossStreet2].where((c) => c != null && c.trim().isNotEmpty).toList();
    return [street, if (cross.length == 2) 'entre ${cross[0]} y ${cross[1]}' else if (cross.length == 1) 'esq. ${cross[0]}'].where((p) => p.isNotEmpty).join(' • ');
  }

  int? positionIn(String? itineraryId) => itineraries.where((i) => i.itineraryId == itineraryId).firstOrNull?.position;

  StopLink? linkIn(String? itineraryId) => itineraries.where((i) => i.itineraryId == itineraryId).firstOrNull;
}

/// Persona (recurso users).
class Person {
  final String id;
  final String? username;
  final PersonName name;
  final String fullName;
  final String? sex;
  final String? photoUrl;
  final bool isAdmin;
  final List<String> entities;
  final String? identityCard;
  final DateTime? birthDate;

  /// Sus Entidades con itinerarios y paradas (solo en GET users/{id}).
  final List<Membership> memberships;

  const Person({required this.id, this.username, this.name = const PersonName(), this.fullName = '', this.sex, this.photoUrl, this.isAdmin = false, this.entities = const [], this.identityCard, this.birthDate, this.memberships = const []});

  factory Person.from(Resource r) => Person(
        id: r.id,
        username: r.string('username'),
        name: PersonName.from(r),
        fullName: r.string('fullName') ?? '',
        sex: r.string('sex'),
        photoUrl: r.string('photoUrl'),
        isAdmin: r.boolean('isAdmin'),
        entities: [for (final e in (r.attributes['entities'] as List? ?? const [])) '$e'],
        identityCard: r.string('identityCard'),
        birthDate: parseDay(r.string('birthDate')),
        memberships: membershipsFrom(r.meta['memberships']),
      );
}

/// Persona en una Entidad (recurso workers, con include=user,entity), con
/// sus itinerarios en ella (meta.itineraries).
class Worker {
  final String id;
  final bool active;
  final Person person;
  final String? entityId;
  final String? entityAbbreviation;
  final List<Placement> itineraries;

  const Worker({required this.id, this.active = true, required this.person, this.entityId, this.entityAbbreviation, this.itineraries = const []});

  factory Worker.from(Resource r) {
    final user = r.related('user');
    final entityId = r.relId('entity')?.id;
    final abbreviation = r.related('entity')?.string('abbreviation');
    return Worker(
      id: r.id,
      active: r.attributes['active'] != false,
      person: user == null ? Person(id: r.relId('user')?.id ?? '') : Person.from(user),
      entityId: entityId,
      entityAbbreviation: abbreviation,
      itineraries: [
        for (final i in (r.meta['itineraries'] as List? ?? const []))
          Placement.fromJson(Map<String, dynamic>.from(i as Map), workerId: r.id, entityId: entityId ?? '', entityAbbreviation: abbreviation ?? ''),
      ],
    );
  }

  bool get isChief => itineraries.any((p) => p.isChief);

  /// «XX Aniversario • Banco Metropolitano» (o «Sin itinerario»).
  String get where => itineraries.isEmpty
      ? 'Sin itinerario'
      : itineraries.map((p) => '${p.itineraryName} • ${p.stopLandmark ?? 'Sin parada'}').join('; ');
}

/// Solicitud de Entidad o de itinerario.
class Application {
  final String id;
  final String type;
  final String status;
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final String? userId;
  final String? userName;
  final String? entityId;
  final String? entityAbbreviation;
  final String? itineraryId;
  final String? itineraryName;
  final String? stopId;
  final String? stopLandmark;
  final String? denialReason;
  final String? resolvedBy;

  const Application({
    required this.id,
    this.type = 'entidad',
    this.status = 'pendiente',
    this.resolutionNote,
    this.resolvedAt,
    this.createdAt,
    this.userId,
    this.userName,
    this.entityId,
    this.entityAbbreviation,
    this.itineraryId,
    this.itineraryName,
    this.stopId,
    this.stopLandmark,
    this.denialReason,
    this.resolvedBy,
  });

  factory Application.from(Resource r) => Application(
        id: r.id,
        type: r.string('type') ?? 'entidad',
        status: r.string('status') ?? 'pendiente',
        resolutionNote: r.string('resolutionNote'),
        resolvedAt: r.date('resolvedAt'),
        createdAt: r.date('createdAt'),
        userId: r.relId('user')?.id,
        userName: r.related('user')?.string('fullName'),
        entityId: r.relId('entity')?.id,
        entityAbbreviation: r.related('entity')?.string('abbreviation'),
        itineraryId: r.relId('itinerary')?.id,
        itineraryName: r.related('itinerary')?.string('name'),
        stopId: r.relId('stop')?.id,
        stopLandmark: r.related('stop')?.string('landmark'),
        denialReason: r.related('denialReason')?.string('name'),
        resolvedBy: r.related('resolvedBy')?.string('fullName'),
      );

  bool get pending => status == 'pendiente';

  bool get isEntity => type == 'entidad';

  String get statusName => const {'pendiente': 'Pendiente', 'aprobada': 'Aprobada', 'rechazada': 'Rechazada'}[status] ?? status;

  /// «Entidad UMIM» / «Itinerario Ruta Playa • Coppelia».
  String get what => isEntity
      ? 'Entidad ${entityAbbreviation ?? ''}'.trim()
      : ['Itinerario ${itineraryName ?? ''}'.trim(), ?stopLandmark].join(' • ');
}

/// Hijo.
class Child {
  final String id;
  final PersonName name;
  final String fullName;
  final String? sex;
  final DateTime? birthDate;
  final DateTime? eligibleUntil;
  final bool eligible;
  final bool active;
  final String? photoUrl;
  final String? identityCard;
  final List<String> otherParents;

  const Child({required this.id, this.name = const PersonName(), this.fullName = '', this.sex, this.birthDate, this.eligibleUntil, this.eligible = true, this.active = true, this.photoUrl, this.identityCard, this.otherParents = const []});

  factory Child.from(Resource r) => Child(
        id: r.id,
        name: PersonName.from(r),
        fullName: r.string('fullName') ?? '',
        sex: r.string('sex'),
        birthDate: parseDay(r.string('birthDate')),
        eligibleUntil: parseDay(r.string('eligibleUntil')),
        eligible: r.attributes['eligible'] != false,
        active: r.attributes['active'] != false,
        photoUrl: r.string('photoUrl'),
        identityCard: r.string('identityCard'),
        otherParents: [for (final p in (r.meta['parents'] as List? ?? const [])) '${(p as Map)['fullName']}'],
      );

  bool get canTravel => eligible && active;
}

/// Elemento de un nomenclador.
class NomenclatorItem {
  final String id;
  final String kind;
  final String name;
  final String? description;
  final String? observation;
  final bool active;
  final int usageCount;
  final int seats;
  final int standing;
  final String? applicationType;

  const NomenclatorItem({required this.id, required this.kind, this.name = '', this.description, this.observation, this.active = true, this.usageCount = 0, this.seats = 0, this.standing = 0, this.applicationType});

  factory NomenclatorItem.from(Resource r) => NomenclatorItem(
        id: r.id,
        kind: r.type,
        name: r.string('name') ?? '',
        description: r.string('description'),
        observation: r.string('observation'),
        active: r.attributes['active'] != false,
        usageCount: _int(r.meta['usageCount']),
        seats: _int(r.attributes['seats']),
        standing: _int(r.attributes['standing']),
        applicationType: r.string('applicationType'),
      );

  int get total => seats + standing;

  /// «Ómnibus (40 + 20 de pie)».
  String get vehicleLabel => '$name ($seats + $standing de pie)';
}

/// Los nomencladores (docs/11 §11.26 y §11.31).
class Nomenclator {
  final String type;
  final String title;
  final String singular;

  final bool feminine;

  const Nomenclator(this.type, this.title, this.singular, {this.feminine = false});

  static const vehicleTypes = Nomenclator('vehicle-types', 'Tipos de vehículo', 'tipo de vehículo');
  static const absenceTypes = Nomenclator('absence-types', 'Tipos de ausencia', 'tipo de ausencia');
  static const conversationTopics = Nomenclator('conversation-topics', 'Motivos de conversación', 'motivo de conversación');
  static const denialReasons = Nomenclator('denial-reasons', 'Motivos de denegación', 'motivo de denegación');
  static const detentionCauses = Nomenclator('detention-causes', 'Causas de detención', 'causa de detención', feminine: true);

  /// «Tipo de vehículo creado», «Causas de detención eliminadas»…
  String done(String verb, {bool plural = false}) {
    final ending = '${feminine ? 'a' : 'o'}${plural ? 's' : ''}';
    final subject = plural ? title : '${singular[0].toUpperCase()}${singular.substring(1)}';
    return '$subject $verb$ending';
  }

  static const all = [vehicleTypes, absenceTypes, conversationTopics, denialReasons, detentionCauses];
}

/// Estados del viaje.
abstract final class TripStatus {
  static const planned = 'planificado';
  static const running = 'en_ejecucion';
  static const finished = 'terminado';
  static const cancelled = 'cancelado';

  static String name(String status) =>
      const {planned: 'Planificado', running: 'En ejecución', finished: 'Terminado', cancelled: 'Cancelado'}[status] ?? status;
}

/// Viaje (de ida o de regreso).
class Trip {
  final String id;
  final String direction;
  final DateTime date;
  final String departureTime;
  final DateTime departsAt;
  final String status;
  final DateTime? statusChangedAt;
  final String? observation;
  final String? vehicleState;
  final bool editable;
  final String itineraryId;
  final String? itineraryName;
  final String? vehicleTypeId;
  final String? vehicleTypeName;
  final String? detentionCauseId;
  final String? createdById;
  final int expectedPassengers;
  final int? capacity;
  final String? myState;

  const Trip({
    required this.id,
    required this.direction,
    required this.date,
    required this.departureTime,
    required this.departsAt,
    required this.status,
    this.statusChangedAt,
    this.observation,
    this.vehicleState,
    this.editable = true,
    required this.itineraryId,
    this.itineraryName,
    this.vehicleTypeId,
    this.vehicleTypeName,
    this.detentionCauseId,
    this.createdById,
    this.expectedPassengers = 0,
    this.capacity,
    this.myState,
  });

  factory Trip.from(Resource r) => Trip(
        id: r.id,
        direction: r.string('direction') ?? 'ida',
        date: parseDay(r.string('date')) ?? DateTime.now(),
        departureTime: r.string('departureTime') ?? '',
        departsAt: r.date('departsAt') ?? DateTime.now(),
        status: r.string('status') ?? TripStatus.planned,
        statusChangedAt: r.date('statusChangedAt'),
        observation: r.string('observation'),
        vehicleState: r.string('vehicleState'),
        editable: r.attributes['editable'] != false,
        itineraryId: r.relId('itinerary')?.id ?? '',
        itineraryName: r.related('itinerary')?.string('name'),
        vehicleTypeId: r.relId('vehicleType')?.id,
        vehicleTypeName: r.related('vehicleType')?.string('name'),
        detentionCauseId: r.relId('detentionCause')?.id,
        createdById: r.relId('createdBy')?.id,
        expectedPassengers: _int(r.meta['expectedPassengers']),
        capacity: r.meta['capacity'] == null ? null : _int(r.meta['capacity']),
        myState: r.meta['myState']?.toString(),
      );

  bool get outbound => direction == 'ida';

  String get directionName => outbound ? 'Ida' : 'Regreso';

  /// «Viaje de ida» / «Viaje de regreso».
  String get title => outbound ? 'Viaje de ida' : 'Viaje de regreso';

  bool get isPlanned => status == TripStatus.planned;

  bool get isRunning => status == TripStatus.running;

  bool get isOpen => isPlanned || isRunning;

  /// «45 de 60 • Normal».
  String get occupancy {
    final cap = capacity;
    if (cap == null || cap == 0) return plural(expectedPassengers, 'trabajador esperado', 'trabajadores esperados');
    final level = expectedPassengers > cap ? 'No caben' : 'Normal';
    return '$expectedPassengers de $cap • $level';
  }
}

/// Estados del trabajador en un viaje (docs/13 §13.8).
abstract final class WorkerState {
  static const onTheWay = 'de_camino';
  static const atStop = 'en_parada';
  static const travelling = 'viajando';
  static const dropped = 'dejado';
  static const pickedUp = 'recogido';
  static const leftBehind = 'botado';
  static const late = 'dormido';
  static const notGoing = 'no_voy';

  static String name(String? state) => const {
        onTheWay: 'De camino a la parada',
        atStop: 'En la parada',
        travelling: 'Viajando',
        dropped: 'Dejado',
        pickedUp: 'Recogido',
        leftBehind: 'Botado',
        late: 'Dormido',
        notGoing: 'No voy a viajar',
      }[state] ??
      'Sin estado';

  /// Nombre corto para las cantidades de la línea.
  static String short(String state) => const {
        onTheWay: 'De camino',
        atStop: 'En la parada',
        travelling: 'Viajando',
        dropped: 'Dejados',
        pickedUp: 'Recogidos',
        leftBehind: 'Botados',
        late: 'Dormidos',
        notGoing: 'No van',
      }[state] ??
      state;
}

/// Una parada en la línea del recorrido.
class LiveStop {
  final int index;
  final String stopId;
  final String landmark;
  final String? street;
  final bool passed;
  final DateTime? passedAt;
  final int expected;
  final Map<String, int> counts;
  final bool mine;

  const LiveStop({required this.index, required this.stopId, this.landmark = '', this.street, this.passed = false, this.passedAt, this.expected = 0, this.counts = const {}, this.mine = false});

  factory LiveStop.fromJson(Map<String, dynamic> j) => LiveStop(
        index: _int(j['index']),
        stopId: '${j['stopId']}',
        landmark: '${j['landmark'] ?? ''}',
        street: _str(j['street']),
        passed: j['passed'] == true,
        passedAt: j['passedAt'] == null ? null : DateTime.tryParse('${j['passedAt']}')?.toLocal(),
        expected: _int(j['expected']),
        counts: j['counts'] is Map ? {for (final e in (j['counts'] as Map).entries) '${e.key}': _int(e.value)} : const {},
        mine: j['mine'] == true,
      );
}

/// Línea del recorrido (GET trips/{id}/live).
class TripLive {
  final String tripId;
  final String direction;
  final String status;
  final DateTime? departsAt;
  final String? vehicleState;
  final DateTime? vehicleSince;
  final bool vehicleAtStop;
  final int nextStopIndex;
  final String? detentionCause;
  final bool longDetention;
  final int sensors;
  final int inVehicleWorkers;
  final int inVehicleChildren;
  final int? capacity;
  final int expectedPassengers;
  final int notGoing;
  final List<LiveStop> stops;
  final String? myState;
  final String? myStopId;
  final bool mySensor;

  const TripLive({
    required this.tripId,
    this.direction = 'ida',
    this.status = TripStatus.planned,
    this.departsAt,
    this.vehicleState,
    this.vehicleSince,
    this.vehicleAtStop = false,
    this.nextStopIndex = 0,
    this.detentionCause,
    this.longDetention = false,
    this.sensors = 0,
    this.inVehicleWorkers = 0,
    this.inVehicleChildren = 0,
    this.capacity,
    this.expectedPassengers = 0,
    this.notGoing = 0,
    this.stops = const [],
    this.myState,
    this.myStopId,
    this.mySensor = false,
  });

  factory TripLive.from(Resource r) {
    final vehicle = Map<String, dynamic>.from(r.attributes['vehicle'] as Map? ?? const {});
    final inVehicle = Map<String, dynamic>.from(r.attributes['inVehicle'] as Map? ?? const {});
    final mine = r.attributes['myState'] is Map ? Map<String, dynamic>.from(r.attributes['myState'] as Map) : null;
    return TripLive(
      tripId: r.id,
      direction: r.string('direction') ?? 'ida',
      status: r.string('status') ?? TripStatus.planned,
      departsAt: r.date('departsAt'),
      vehicleState: _str(vehicle['state']),
      vehicleSince: vehicle['since'] == null ? null : DateTime.tryParse('${vehicle['since']}')?.toLocal(),
      vehicleAtStop: vehicle['atStop'] == true,
      nextStopIndex: _int(vehicle['nextStopIndex']),
      detentionCause: vehicle['detentionCause'] is Map ? _str((vehicle['detentionCause'] as Map)['name']) : null,
      longDetention: vehicle['longDetention'] == true,
      sensors: _int(r.attributes['sensors']),
      inVehicleWorkers: _int(inVehicle['workers']),
      inVehicleChildren: _int(inVehicle['children']),
      capacity: inVehicle['capacity'] == null ? null : _int(inVehicle['capacity']),
      expectedPassengers: _int(r.attributes['expectedPassengers']),
      notGoing: _int(r.attributes['notGoing']),
      stops: [for (final s in (r.attributes['stops'] as List? ?? const [])) LiveStop.fromJson(Map<String, dynamic>.from(s as Map))],
      myState: _str(mine?['state']),
      myStopId: _str(mine?['stopId']),
      mySensor: mine?['sensor'] == true,
    );
  }

  bool get outbound => direction == 'ida';

  /// La parada de la persona en el recorrido (o null).
  LiveStop? get myStop => stops.where((s) => s.mine).firstOrNull;
}

/// Ajuste de la app (recurso settings; id = clave).
class Setting {
  final String key;
  final String name;
  final String group;
  final String groupName;
  final String type;
  final String value;
  final num? base;
  final String? defaultValue;
  final String? description;

  const Setting({required this.key, this.name = '', this.group = '', this.groupName = '', this.type = 'entero', this.value = '', this.base, this.defaultValue, this.description});

  factory Setting.from(Resource r) => Setting(
        key: r.id,
        name: r.string('name') ?? r.id,
        group: r.string('group') ?? '',
        groupName: r.string('groupName') ?? '',
        type: r.string('type') ?? 'entero',
        value: r.string('value') ?? '',
        base: r.attributes['base'] as num?,
        defaultValue: r.string('defaultValue'),
        description: r.string('description'),
      );
}

/// Versión publicada de la app.
class AppVersion {
  final String id;
  final String versionName;
  final int versionCode;
  final String? notes;
  final bool mandatory;
  final DateTime? publishedAt;
  final List<Map<String, dynamic>> files;
  final int installedCount;

  const AppVersion({required this.id, this.versionName = '', this.versionCode = 0, this.notes, this.mandatory = false, this.publishedAt, this.files = const [], this.installedCount = 0});

  factory AppVersion.from(Resource r) => AppVersion(
        id: r.id,
        versionName: r.string('versionName') ?? '',
        versionCode: r.integer('versionCode') ?? 0,
        notes: r.string('notes'),
        mandatory: r.boolean('mandatory'),
        publishedAt: r.date('publishedAt'),
        files: [for (final f in (r.attributes['files'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)],
        installedCount: _int(r.meta['installedCount']),
      );
}

/// Conversación con el desarrollador.
class Conversation {
  final String id;
  final String? topic;
  final String? userName;
  final String? lastMessage;
  final DateTime? updatedAt;
  final bool unread;

  const Conversation({required this.id, this.topic, this.userName, this.lastMessage, this.updatedAt, this.unread = false});

  factory Conversation.from(Resource r) => Conversation(
        id: r.id,
        topic: r.related('topic')?.string('name'),
        userName: r.related('user')?.string('fullName'),
        lastMessage: r.string('lastMessage'),
        updatedAt: r.date('lastMessageAt') ?? r.date('createdAt'),
        unread: r.boolean('unread'),
      );
}

class Message {
  final String id;
  final String body;
  final bool fromDeveloper;
  final bool mine;
  final DateTime createdAt;

  const Message({required this.id, required this.body, this.fromDeveloper = false, this.mine = false, required this.createdAt});

  factory Message.from(Resource r) => Message(
        id: r.id,
        body: r.string('body') ?? '',
        fromDeveloper: r.boolean('fromDeveloper'),
        mine: r.boolean('mine'),
        createdAt: r.date('createdAt') ?? DateTime.now(),
      );
}
