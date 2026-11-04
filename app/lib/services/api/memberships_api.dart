import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';

/// Pertenencias y solicitudes de la persona (docs/11 §11.5, §11.6 y §11.16).
///
/// Entrar en una Entidad y darse de baja de ella, y el Administrador que entra
/// sin solicitud, están en Session (joinEntity, leaveEntity) porque cambian /me.
class MembershipsApi {
  final ApiClient api;

  const MembershipsApi(this.api);

  /// Busca una Entidad por su abreviatura (nunca se muestra la lista).
  Future<Entity> lookupEntity(String abbreviation) async =>
      Entity.from((await api.get('/entities/lookup', query: {'abbreviation': abbreviation.trim()})).resource);

  // Solicitudes

  /// Sus solicitudes (por defecto, las pendientes).
  Future<List<Application>> myApplications({String? status = ApplicationStatus.pending, String? type, String? entityId}) async =>
      (await api.getAll('/applications', query: {
        'filter[mine]': 'true',
        'filter[status]': ?status,
        'filter[type]': ?type,
        'filter[entity]': ?entityId,
        'include': 'entity,itinerary,stop,role',
      }))
          .map(Application.from)
          .toList();

  /// Solicitar entrar en una Entidad (la aprueba quien tenga entities.approve_membership).
  Future<Application> requestEntity(String abbreviation) => _apply(ApplicationType.entityMembership, attributes: {'entityAbbreviation': abbreviation.trim()});

  /// Solicitar itinerario y parada (siempre juntos) en una Entidad a la que pertenece.
  Future<Application> requestItinerary({required String itineraryId, required String stopId}) => _apply(ApplicationType.itineraryMembership,
      relationships: {'itinerary': ResourceId('itineraries', itineraryId), 'stop': ResourceId('stops', stopId)});

  /// Solicitar un rol en una Entidad ([itineraryId] si el rol es por itinerario).
  Future<Application> requestRole({required String roleId, required String entityId, String? itineraryId}) => _apply(ApplicationType.role, relationships: {
        'role': ResourceId('roles', roleId),
        'entity': ResourceId('entities', entityId),
        if (itineraryId != null) 'itinerary': ResourceId('itineraries', itineraryId),
      });

  Future<Application> _apply(String type, {Map<String, dynamic> attributes = const {}, Map<String, ResourceId?>? relationships}) async =>
      Application.from((await api.post('/applications', resourceData('applications', attributes: {'type': type, ...attributes}, relationships: relationships))).resource);

  /// Cancelar una solicitud propia pendiente.
  Future<void> cancelApplication(String id) => api.patch('/applications/$id', resourceData('applications', id: id, attributes: {'status': ApplicationStatus.cancelled}));

  /// Aprobar o rechazar (el motivo es obligatorio al rechazar).
  Future<void> resolveApplication(String id, {required bool approve, String? note}) => api.patch('/applications/$id',
      resourceData('applications', id: id, attributes: {'status': approve ? ApplicationStatus.approved : ApplicationStatus.rejected, 'resolutionNote': ?note}));

  // Itinerario y parada

  /// Darse de baja del itinerario (y su parada) en esa pertenencia.
  Future<void> leaveItinerary(String workerId) => api.delete('/workers/$workerId/itinerary');

  /// Itinerarios de una Entidad (para solicitar uno).
  Future<List<Itinerary>> itineraries(String entityId) async =>
      (await api.getAll('/itineraries', query: {'filter[entity]': entityId, 'sort': 'name'})).map(Itinerary.from).toList();

  /// Paradas de un itinerario, en orden.
  Future<List<Stop>> stopsOf(String itineraryId) async =>
      (await api.getAll('/itinerary-stops', query: {'filter[itinerary]': itineraryId, 'include': 'stop', 'sort': 'position'}))
          .map(ItineraryStop.from)
          .map((link) => link.stop!)
          .toList();
}
