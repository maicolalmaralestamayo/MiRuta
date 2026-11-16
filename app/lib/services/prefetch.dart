import '../core/api_client.dart';
import '../core/storage.dart';
import 'sync.dart';

/// Descarga en segundo plano todo lo que la persona puede ver (docs/11
/// §11.65): tras el inicio de sesión y cuando el registro de cambios pide
/// volver a descargarlo todo. Hace las mismas consultas que las pantallas
/// (mismas claves de la caché), así estas abren con los datos del teléfono.
class Prefetch {
  static bool _running = false;

  static Future<void> run(ApiClient api) async {
    if (_running) return;
    _running = true;
    try {
      final me = await Storage.getJson(SyncService.meKey);
      if (me['userId'] == null) return;
      final userId = '${me['userId']}';
      final admin = me['isAdmin'] == true;
      final chief = me['chiefItineraryId']?.toString();
      final itineraries = {for (final id in (me['itineraryIds'] as List? ?? const [])) '$id', ?chief};
      final manages = admin || chief != null;
      final loads = <Future<Object?> Function()>[
        () => api.getAll('/applications', query: {'filter[mine]': 'true', 'include': 'entity,itinerary,stop,denialReason,resolvedBy'}),
        () => api.getAll('/children', query: {'filter[parent]': userId}),
        () => api.getAll('/absences', query: {'filter[user]': userId, 'filter[current]': 'true'}),
        () => api.getAll('/entities'),
        () => api.getAll('/itineraries', query: {'include': 'entity'}),
        () => api.getAll('/trips', query: {'include': 'itinerary,vehicleType', 'sort': 'departsAt', 'filter[status]': 'planificado,en_ejecucion,terminado'}),
        () => api.getAll('/vehicle-types', query: {'filter[active]': 'true'}),
        () => api.getAll('/absence-types', query: {'filter[active]': 'true'}),
        () => api.getAll('/conversation-topics', query: {'filter[active]': 'true'}),
        () => api.getAll('/conversations', query: {'include': 'topic,user'}),
        for (final id in itineraries) () => api.getAll('/stops', query: {'filter[itinerary]': id, 'sort': 'position'}),
        if (manages) () => api.getAll('/stops'),
        if (manages) () => api.getAll('/users'),
        if (manages) () => api.getAll('/detention-causes', query: {'filter[active]': 'true'}),
        if (manages) () => api.getAll('/entity-denial-reasons', query: {'filter[active]': 'true'}),
        if (manages) () => api.getAll('/itinerary-denial-reasons', query: {'filter[active]': 'true'}),
        if (manages) () => api.getAll('/applications', query: {'filter[type]': 'itinerario', 'filter[status]': 'pendiente', 'include': 'user,entity,itinerary,stop'}),
        if (admin) () => api.getAll('/applications', query: {'filter[type]': 'entidad', 'filter[status]': 'pendiente', 'include': 'user,entity,itinerary,stop'}),
        for (final id in itineraries) () => api.getAll('/worker-itineraries', query: {'filter[itinerary]': id}),
      ];
      for (final load in loads) {
        try {
          await load();
        } catch (_) {
          // Sin conexión o sin permiso: se sigue con lo demás.
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Vuelve a pedir por detrás las listas marcadas (tipos con altas).
  static Future<bool> refreshStale(ApiClient api, Set<String> keys, {int limit = 20}) async {
    var any = false;
    for (final key in keys.take(limit)) {
      final parts = key.split('?');
      final query = <String, dynamic>{
        if (parts.length > 1)
          for (final p in parts[1].split('&'))
            if (p.contains('=')) p.substring(0, p.indexOf('=')): p.substring(p.indexOf('=') + 1),
      };
      try {
        await api.get(parts.first, query: query);
        any = true;
      } catch (_) {}
    }
    return any;
  }
}
