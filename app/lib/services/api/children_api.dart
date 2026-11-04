import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';

/// Hijos de la persona (docs/11 §11.11): se añaden, corrigen y quitan
/// directamente, sin solicitud.
class ChildrenApi {
  final ApiClient api;

  const ChildrenApi(this.api);

  /// Sus hijos. [eligible] true = solo con derecho a viajar; [active] filtra
  /// activos o desactivados.
  Future<List<Child>> mine(String userId, {bool? eligible, bool? active}) async => (await api.getAll('/children', query: {
        'filter[parent]': userId,
        if (eligible != null) 'filter[eligible]': '$eligible',
        if (active != null) 'filter[active]': '$active',
      }))
          .map(Child.from)
          .toList();

  Future<Child> get(String id) async => Child.from((await api.get('/children/$id')).resource);

  /// Añadir por carné. Si ya estaba registrado se vincula y
  /// [ChildAdded.alreadyDeclared] es true (con el aviso del servidor).
  Future<ChildAdded> add({required PersonName name, required String identityCard}) async {
    final document = await api.post('/children', resourceData('children', attributes: {...name.toAttributes(), 'identityCard': identityCard.trim()}));
    final resource = document.resource;
    return ChildAdded(Child.from(resource), resource.meta['alreadyDeclared'] == true, document.meta['notice'] as String?);
  }

  Future<Child> update(String id, {PersonName? name, String? identityCard}) async => Child.from((await api.patch('/children/$id', resourceData('children', id: id, attributes: {
        ...?name?.toAttributes(),
        if (identityCard != null) 'identityCard': identityCard.trim(),
      })))
          .resource);

  /// Desactivar o reactivar (reactivar exige que tenga derecho).
  Future<Child> setActive(String id, bool active) async =>
      Child.from((await api.patch('/children/$id', resourceData('children', id: id, attributes: {'active': active}))).resource);

  /// Quitarlo (lo desvincula de quien lo pide).
  Future<void> remove(String id) => api.delete('/children/$id');

  Future<void> uploadPhoto(String id, String path) => api.upload('/children/$id/photo', 'photo', path);

  Future<void> deletePhoto(String id) => api.delete('/children/$id/photo');
}

class ChildAdded {
  final Child child;
  final bool alreadyDeclared;
  final String? notice;

  ChildAdded(this.child, this.alreadyDeclared, this.notice);
}
