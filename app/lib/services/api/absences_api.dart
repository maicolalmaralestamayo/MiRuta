import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';

/// Ausencias sin aprobación (docs/11 §11.12): las declara la propia persona.
class AbsencesApi {
  final ApiClient api;

  const AbsencesApi(this.api);

  /// Sus ausencias (de una pertenencia, si se indica).
  Future<List<Absence>> mine({String? workerId}) async => (await api.getAll('/absences', query: {
        'filter[mine]': 'true',
        'filter[worker]': ?workerId,
        'include': 'absenceType',
        'sort': '-startsOn',
      }))
          .map(Absence.from)
          .toList();

  Future<List<Named>> types() async => (await api.getAll('/absence-types', query: {'sort': 'name'})).map(Named.from).toList();

  /// Declarar: sin [endsOn] es indefinida. [workerId] = la pertenencia (obligatoria si tiene varias).
  Future<Absence> create({required String workerId, required String absenceTypeId, required DateTime startsOn, DateTime? endsOn, String? note}) async =>
      Absence.from((await api.post('/absences', resourceData('absences', attributes: _attributes(startsOn, endsOn, note), relationships: {
        'worker': ResourceId('workers', workerId),
        'absenceType': ResourceId('absence-types', absenceTypeId),
      })))
          .resource);

  Future<Absence> update(String id, {required String absenceTypeId, required DateTime startsOn, DateTime? endsOn, String? note}) async =>
      Absence.from((await api.patch('/absences/$id', resourceData('absences', id: id, attributes: _attributes(startsOn, endsOn, note), relationships: {
        'absenceType': ResourceId('absence-types', absenceTypeId),
      })))
          .resource);

  Future<void> delete(String id) => api.delete('/absences/$id');

  static String day(DateTime date) => date.toIso8601String().substring(0, 10);

  Map<String, dynamic> _attributes(DateTime startsOn, DateTime? endsOn, String? note) => {
        'startsOn': day(startsOn),
        'endsOn': endsOn == null ? null : day(endsOn),
        'indefinite': endsOn == null,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      };
}
