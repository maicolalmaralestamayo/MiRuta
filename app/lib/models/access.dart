/// Pertenencias, roles y permisos (docs/11 §11.6, §11.16; docs/04-api.md §4.3).
library;

import '../core/json_api.dart';
import 'person.dart';

/// Claves del catálogo fijo de operaciones (api/app/Support/Operations.php).
/// Lo «propio» (perfil, mis hijos, mis ausencias, mis solicitudes, mis ajustes,
/// mi QR) no es una operación: lo puede siempre cada persona.
abstract final class Op {
  static const workersView = 'workers.view';
  static const workersRegister = 'workers.register';
  static const workersEdit = 'workers.edit';
  static const workersDeactivate = 'workers.deactivate';
  static const workersDelete = 'workers.delete';
  static const workersViewIdentityCard = 'workers.view_identity_card';
  static const workersPrintedQr = 'workers.printed_qr';
  static const childrenView = 'children.view';
  static const childrenManage = 'children.manage';
  static const entitiesView = 'entities.view';
  static const entitiesManage = 'entities.manage';
  static const entitiesApproveMembership = 'entities.approve_membership';
  static const entitiesAssignMembers = 'entities.assign_members';
  static const itinerariesView = 'itineraries.view';
  static const itinerariesManage = 'itineraries.manage';
  static const stopsManage = 'stops.manage';
  static const itinerariesOrderStops = 'itineraries.order_stops';
  static const itinerariesReferenceRoute = 'itineraries.reference_route';
  static const membersApprove = 'members.approve';
  static const membersAssign = 'members.assign';
  static const membersAssignByQr = 'members.assign_by_qr';
  static const rolesView = 'roles.view';
  static const rolesManage = 'roles.manage';
  static const rolesSetDefault = 'roles.set_default';
  static const rolesAssign = 'roles.assign';
  static const rolesApprove = 'roles.approve';
  static const vehiclesView = 'vehicles.view';
  static const vehiclesManage = 'vehicles.manage';
  static const vehiclesAssignDriver = 'vehicles.assign_driver';
  static const tripsView = 'trips.view';
  static const tripsPlan = 'trips.plan';
  static const tripsEdit = 'trips.edit';
  static const tripsConfirmCancel = 'trips.confirm_cancel';
  static const tripsDelete = 'trips.delete';
  static const tripsComplete = 'trips.complete';
  static const trackingDrive = 'tracking.drive';
  static const trackingViewLive = 'tracking.view_live';
  static const trackingScanBoarding = 'tracking.scan_boarding';
  static const trackingAllowOutsiders = 'tracking.allow_outsiders';
  static const trackingFixPassengers = 'tracking.fix_passengers';
  static const absencesView = 'absences.view';
  static const absencesManage = 'absences.manage';
  static const absenceTypesManage = 'absence_types.manage';
  static const settingsApp = 'settings.app';
  static const settingsEntity = 'settings.entity';
  static const settingsItinerary = 'settings.itinerary';
  static const settingsWorker = 'settings.worker';
  static const nomenclatorsManage = 'nomenclators.manage';
  static const chatRoleConversations = 'chat.role_conversations';
  static const chatDeleteMessages = 'chat.delete_messages';
  static const statisticsView = 'statistics.view';
  static const accessRecoveriesManage = 'access_recoveries.manage';
  static const appVersionsManage = 'app_versions.manage';
  static const maintenanceRun = 'maintenance.run';
}

/// Ámbitos de una operación.
abstract final class Scope {
  static const own = 'own';
  static const itinerary = 'itinerary';
  static const entity = 'entity';
  static const all = 'all';

  static String label(String scope) => const {own: 'Propio', itinerary: 'Su itinerario', entity: 'Su Entidad', all: 'Todas'}[scope] ?? scope;
}

/// Una línea de `meta.permissions` de GET /me: puede hacer [operation] con
/// ese [scope] en [entityId] (y, con ámbito itinerario, en [itineraryId]).
class Permission {
  final String operation;
  final String scope;
  final String? entityId;
  final String? itineraryId;

  const Permission({required this.operation, required this.scope, this.entityId, this.itineraryId});

  factory Permission.fromJson(Map<String, dynamic> j) => Permission(
        operation: '${j['operation']}',
        scope: '${j['scope']}',
        entityId: j['entityId']?.toString(),
        itineraryId: j['itineraryId']?.toString(),
      );

  Map<String, dynamic> toJson() => {'operation': operation, 'scope': scope, 'entityId': entityId, 'itineraryId': itineraryId};
}

/// Los permisos de la persona, con la misma semántica que
/// `App\Services\Permissions` en la API:
/// - `all`: en todo;
/// - `entity`: en esa Entidad (o en cualquier itinerario suyo);
/// - `itinerary`: en ese itinerario;
/// - `own`: no cuenta en [can] (lo propio se permite siempre); ver [canOwn].
class Permissions {
  final bool isAdmin;
  final List<Permission> items;

  /// Entidad de cada itinerario conocido (de los permisos y las pertenencias),
  /// para resolver `entity` cuando solo se pasa el itinerario.
  final Map<String, String> _itineraryEntity;

  Permissions(this.items, {this.isAdmin = false, Map<String, String> itineraryEntities = const {}})
      : _itineraryEntity = {
          for (final p in items)
            if (p.itineraryId != null && p.entityId != null) p.itineraryId!: p.entityId!,
          ...itineraryEntities,
        };

  static final none = Permissions(const []);

  factory Permissions.fromJson(List<dynamic>? list, {bool isAdmin = false, Map<String, String> itineraryEntities = const {}}) =>
      Permissions([for (final item in list ?? const []) Permission.fromJson(Map<String, dynamic>.from(item as Map))],
          isAdmin: isAdmin, itineraryEntities: itineraryEntities);

  List<Map<String, dynamic>> toJson() => [for (final p in items) p.toJson()];

  /// Puede hacer [operation] sobre esa Entidad y/o ese itinerario. Sin
  /// Entidad ni itinerario solo vale el ámbito `all`. Pase la Entidad también
  /// cuando pase el itinerario (si no, se deduce de lo que se conoce).
  bool can(String operation, {String? entityId, String? itineraryId}) {
    if (isAdmin) return true;
    final entity = entityId ?? (itineraryId == null ? null : _itineraryEntity[itineraryId]);
    for (final p in items) {
      if (p.operation != operation) continue;
      switch (p.scope) {
        case Scope.all:
          return true;
        case Scope.entity:
          if (entity != null && p.entityId == entity) return true;
        case Scope.itinerary:
          if (itineraryId != null && p.itineraryId == itineraryId) return true;
      }
    }
    return false;
  }

  /// Tiene la operación con algún ámbito (para mostrar u ocultar entradas de
  /// menú). Con [includeOwn], también el ámbito `own`.
  bool canAnywhere(String operation, {bool includeOwn = false}) =>
      isAdmin || items.any((p) => p.operation == operation && (includeOwn || p.scope != Scope.own));

  /// Tiene la operación en esa Entidad, en la Entidad entera o en alguno de
  /// sus itinerarios (no `own`).
  bool canInEntity(String operation, String entityId) =>
      isAdmin || items.any((p) => p.operation == operation && p.scope != Scope.own && (p.scope == Scope.all || p.entityId == entityId));

  /// Tiene la operación en esa Entidad con cualquier ámbito, también `own`.
  bool canOwn(String operation, String entityId) =>
      isAdmin || items.any((p) => p.operation == operation && (p.scope == Scope.all || p.entityId == entityId));

  /// Entidades en las que tiene la operación (null = todas).
  Set<String>? entitiesFor(String operation) {
    if (isAdmin || items.any((p) => p.operation == operation && p.scope == Scope.all)) return null;
    return {for (final p in items) if (p.operation == operation && p.scope != Scope.own && p.entityId != null) p.entityId!};
  }

  /// Itinerarios en los que tiene la operación solo con ámbito itinerario.
  Set<String> itinerariesFor(String operation) =>
      {for (final p in items) if (p.operation == operation && p.scope == Scope.itinerary && p.itineraryId != null) p.itineraryId!};
}

/// Entidad (recurso `entities`, o la versión resumida de las pertenencias).
class Entity {
  final String id;
  final String abbreviation;
  final String name;
  final String? number;
  final String? description;
  final String? observation;
  final String? imageUrl;
  final int workerCount;
  final bool active;

  const Entity({
    required this.id,
    required this.abbreviation,
    required this.name,
    this.number,
    this.description,
    this.observation,
    this.imageUrl,
    this.workerCount = 0,
    this.active = true,
  });

  factory Entity.from(Resource r) => Entity(
        id: r.id,
        abbreviation: r.string('abbreviation') ?? '',
        name: r.string('name') ?? '',
        number: r.string('number'),
        description: r.string('description'),
        observation: r.string('observation'),
        imageUrl: r.string('imageUrl'),
        workerCount: r.integer('workerCount') ?? 0,
        active: r.attributes['active'] != false,
      );

  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
        id: '${j['id']}',
        abbreviation: '${j['abbreviation'] ?? ''}',
        name: '${j['name'] ?? ''}',
        imageUrl: j['imageUrl'] as String?,
        workerCount: (j['workerCount'] as num?)?.toInt() ?? 0,
      );
}

/// Rol que tiene una persona en una Entidad (`worker-roles`, o `roles` de
/// `meta.memberships` / `meta.roles` de un trabajador).
class HeldRole {
  /// Id de la asignación (`worker-roles`): para darse de baja del rol.
  final String id;
  final String roleId;
  final String name;

  /// Nombre de un ícono Material (ver `roleIcon` en ui/widgets/cards.dart).
  final String? icon;
  final bool isDefault;
  final String? itineraryId;
  final String? itineraryName;

  const HeldRole({required this.id, required this.roleId, required this.name, this.icon, this.isDefault = false, this.itineraryId, this.itineraryName});

  factory HeldRole.fromJson(Map<String, dynamic> j) => HeldRole(
        id: '${j['id']}',
        roleId: '${j['roleId']}',
        name: '${j['name'] ?? ''}',
        icon: j['icon'] as String?,
        isDefault: j['isDefault'] == true,
        itineraryId: j['itineraryId']?.toString(),
        itineraryName: j['itineraryName'] as String?,
      );

  /// Desde GET /worker-roles (include=role,itinerary).
  factory HeldRole.from(Resource r) => HeldRole(
        id: r.id,
        roleId: r.relId('role')?.id ?? '',
        name: r.string('roleName') ?? r.related('role')?.string('name') ?? '',
        icon: r.string('icon'),
        isDefault: r.related('role')?.boolean('isDefault') ?? false,
        itineraryId: r.relId('itinerary')?.id,
        itineraryName: r.related('itinerary')?.string('name'),
      );
}

/// Pertenencia de la persona a una Entidad (`meta.memberships` de GET /me):
/// su itinerario y parada (siempre juntos) y sus roles allí.
class Membership {
  /// Id de la pertenencia (recurso `workers`).
  final String workerId;
  final Entity entity;
  final MembershipItinerary? itinerary;
  final MembershipStop? stop;
  final List<HeldRole> roles;

  const Membership({required this.workerId, required this.entity, this.itinerary, this.stop, this.roles = const []});

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        workerId: '${j['workerId']}',
        entity: Entity.fromJson(Map<String, dynamic>.from(j['entity'] as Map)),
        itinerary: j['itinerary'] == null ? null : MembershipItinerary.fromJson(Map<String, dynamic>.from(j['itinerary'] as Map)),
        stop: j['stop'] == null ? null : MembershipStop.fromJson(Map<String, dynamic>.from(j['stop'] as Map)),
        roles: [for (final r in (j['roles'] as List? ?? const [])) HeldRole.fromJson(Map<String, dynamic>.from(r as Map))],
      );

  String get entityId => entity.id;

  String? get itineraryId => itinerary?.id;

  String? get stopId => stop?.id;

  bool get hasItinerary => itinerary != null && stop != null;

  /// Roles aprobados que no son el rol por defecto (Trabajador), que se
  /// muestra aparte y siempre primero (docs/11 §11.10).
  List<HeldRole> get extraRoles => roles.where((r) => !r.isDefault).toList();
}

class MembershipItinerary {
  final String id;
  final String name;
  final String? imageUrl;
  final int memberCount;

  const MembershipItinerary({required this.id, required this.name, this.imageUrl, this.memberCount = 0});

  factory MembershipItinerary.fromJson(Map<String, dynamic> j) =>
      MembershipItinerary(id: '${j['id']}', name: '${j['name'] ?? ''}', imageUrl: j['imageUrl'] as String?, memberCount: (j['memberCount'] as num?)?.toInt() ?? 0);
}

class MembershipStop {
  final String id;
  final String landmark;
  final String street;
  final String? imageUrl;

  const MembershipStop({required this.id, required this.landmark, this.street = '', this.imageUrl});

  factory MembershipStop.fromJson(Map<String, dynamic> j) =>
      MembershipStop(id: '${j['id']}', landmark: '${j['landmark'] ?? ''}', street: '${j['street'] ?? ''}', imageUrl: j['imageUrl'] as String?);
}

/// La persona con sesión: sus datos, sus pertenencias y sus permisos.
///
/// El Administrador (`isAdmin`) puede todo en todas las Entidades; además
/// puede pertenecer a Entidades como un trabajador más (docs/11 §11.13).
class Me {
  final Person person;
  final List<Membership> memberships;
  final Permissions permissions;

  Me(this.person, this.memberships, this.permissions);

  factory Me.from(Resource r) {
    final person = Person.from(r);
    final memberships = [for (final m in (r.meta['memberships'] as List? ?? const [])) Membership.fromJson(Map<String, dynamic>.from(m as Map))];
    return Me(
      person,
      memberships,
      Permissions.fromJson(r.meta['permissions'] as List?, isAdmin: person.isAdmin, itineraryEntities: {
        for (final m in memberships)
          if (m.itineraryId != null) m.itineraryId!: m.entityId,
        for (final m in memberships)
          for (final role in m.roles)
            if (role.itineraryId != null) role.itineraryId!: m.entityId,
      }),
    );
  }

  /// Id de la persona (recurso `users`).
  String get id => person.id;

  String get userId => person.id;

  bool get isAdmin => person.isAdmin;

  String? get username => person.username;

  PersonName get name => person.name;

  String get fullName => person.fullName;

  String get firstName => person.name.firstName;

  String? get photoUrl => person.photoUrl;

  bool get mustChangePassword => person.mustChangePassword;

  bool get hasEntity => memberships.isNotEmpty;

  /// Su pertenencia a esa Entidad, si la tiene.
  Membership? membershipIn(String? entityId) {
    for (final m in memberships) {
      if (m.entityId == entityId) return m;
    }
    return null;
  }

  /// Su pertenencia con ese id de trabajador (p. ej. el chofer de un viaje).
  Membership? membershipByWorker(String? workerId) {
    for (final m in memberships) {
      if (m.workerId == workerId) return m;
    }
    return null;
  }

  Set<String> get workerIds => {for (final m in memberships) m.workerId};

  Set<String> get itineraryIds => {for (final m in memberships) if (m.itineraryId != null) m.itineraryId!};

  /// Es miembro de ese itinerario (en alguna de sus Entidades).
  bool isMemberOf(String? itineraryId) => itineraryId != null && itineraryIds.contains(itineraryId);

  /// Su parada en ese itinerario.
  String? stopIdIn(String? itineraryId) {
    for (final m in memberships) {
      if (m.itineraryId != null && m.itineraryId == itineraryId) return m.stopId;
    }
    return null;
  }

  /// Ver [Permissions.can].
  bool can(String operation, {String? entityId, String? itineraryId}) => permissions.can(operation, entityId: entityId, itineraryId: itineraryId);

  bool canAnywhere(String operation) => permissions.canAnywhere(operation);

  bool canInEntity(String operation, String entityId) => permissions.canInEntity(operation, entityId);
}

/// Rol configurable (recurso `roles`). El Administrador aparece como rol
/// virtual de solo lectura con id `admin`.
class Role {
  final String id;
  final String name;
  final String? icon;
  final bool requestable;
  final bool isDefault;
  final bool itineraryScoped;
  final bool isAdministrator;
  final bool editable;

  /// Solo con roles.view / roles.manage.
  final List<({String operation, String scope})> permissions;
  final List<String> approverRoleIds;
  final int? holderCount;

  const Role({
    required this.id,
    required this.name,
    this.icon,
    this.requestable = false,
    this.isDefault = false,
    this.itineraryScoped = false,
    this.isAdministrator = false,
    this.editable = true,
    this.permissions = const [],
    this.approverRoleIds = const [],
    this.holderCount,
  });

  factory Role.from(Resource r) => Role(
        id: r.id,
        name: r.string('name') ?? '',
        icon: r.string('icon'),
        requestable: r.boolean('requestable'),
        isDefault: r.boolean('isDefault'),
        itineraryScoped: r.boolean('itineraryScoped'),
        isAdministrator: r.boolean('isAdministrator'),
        editable: r.attributes['editable'] != false,
        permissions: [
          for (final p in (r.attributes['permissions'] as List? ?? const [])) (operation: '${(p as Map)['operation']}', scope: '${p['scope']}'),
        ],
        approverRoleIds: ((r.attributes['approverRoleIds'] as List?) ?? const []).map((e) => '$e').toList(),
        holderCount: r.integer('holderCount'),
      );
}

/// Operación del catálogo (GET /operations).
class Operation {
  final String key;
  final String group;
  final String name;
  final List<String> scopes;

  const Operation({required this.key, required this.group, required this.name, this.scopes = const []});

  factory Operation.from(Resource r) => Operation(
        key: r.string('key') ?? r.id,
        group: r.string('group') ?? '',
        name: r.string('name') ?? '',
        scopes: ((r.attributes['scopes'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}
