import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';

/// Roles configurables (docs/11 §11.16).
class RolesApi {
  final ApiClient api;

  const RolesApi(this.api);

  /// Todos los roles (cualquiera con sesión; los detalles, con roles.view).
  /// El primero es el rol virtual del Administrador (id `admin`).
  Future<List<Role>> all() async => (await api.getAll('/roles')).map(Role.from).toList();

  /// Los que se pueden solicitar.
  Future<List<Role>> requestable() async => (await all()).where((r) => r.requestable && !r.isAdministrator).toList();

  Future<Role> get(String id) async => Role.from((await api.get('/roles/$id')).resource);

  /// Catálogo fijo de operaciones (roles.view).
  Future<List<Operation>> operations() async => (await api.getAll('/operations')).map(Operation.from).toList();

  /// Asignaciones de roles (filtros: worker, entity, role, itinerary, user).
  Future<List<HeldRole>> assignments(Map<String, String> filters) async =>
      (await api.getAll('/worker-roles', query: {for (final f in filters.entries) 'filter[${f.key}]': f.value, 'include': 'role,itinerary'}))
          .map(HeldRole.from)
          .toList();

  /// Choferes: pertenencias con un rol que tiene tracking.drive (por
  /// ejemplo, para elegir el chofer de un viaje). Si no se pueden ver las
  /// operaciones de los roles (roles.view), se usa el rol «Chofer».
  Future<List<Worker>> drivers({String? entityId}) async {
    final roles = await all();
    var driving = roles.where((r) => r.permissions.any((p) => p.operation == Op.trackingDrive)).map((r) => r.id).toSet();
    if (driving.isEmpty) driving = roles.where((r) => r.name.toLowerCase() == 'chofer').map((r) => r.id).toSet();
    final workers = <String, Worker>{};
    for (final roleId in driving) {
      final resources = await api.getAll('/worker-roles', query: {'filter[role]': roleId, 'filter[entity]': ?entityId, 'include': 'worker'});
      for (final r in resources) {
        final worker = r.related('worker');
        if (worker != null) workers[worker.id] = Worker.from(worker);
      }
    }
    return workers.values.toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  /// Asignar directamente (roles.assign).
  Future<void> assign({required String workerId, required String roleId, String? itineraryId}) => api.post('/worker-roles', resourceData('worker-roles', relationships: {
        'worker': ResourceId('workers', workerId),
        'role': ResourceId('roles', roleId),
        if (itineraryId != null) 'itinerary': ResourceId('itineraries', itineraryId),
      }));

  /// Darse de baja de un rol propio o quitárselo a otro ([workerRoleId] = `HeldRole.id`).
  Future<void> remove(String workerRoleId) => api.delete('/worker-roles/$workerRoleId');
}
