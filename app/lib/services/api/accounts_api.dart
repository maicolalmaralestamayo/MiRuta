import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';

/// Cuentas sin sesión (docs/11 §11.5 y §11.7): estado del registro,
/// usuario y contraseña propuestos y «Olvidé algo». El registro, el inicio de
/// sesión y el perfil propio están en Session.
class AccountsApi {
  final ApiClient api;

  const AccountsApi(this.api);

  /// Si ya hay Administrador. Si no, quien se registre lo será.
  Future<bool> adminExists() async => (await api.get('/registration-status', guest: false)).resource.boolean('adminExists');

  /// Usuario propuesto a partir de los nombres (público).
  Future<String> usernameSuggestion(PersonName name) async {
    final document = await api.get('/username-suggestion', query: {
      'firstName': name.firstName.trim(),
      if (name.middleName.trim().isNotEmpty) 'middleName': name.middleName.trim(),
      'firstSurname': name.firstSurname.trim(),
      'secondSurname': name.secondSurname.trim(),
    });
    return document.resource.string('username') ?? '';
  }

  /// Contraseña propuesta que cumple la política (público).
  Future<String> passwordSuggestion() async => (await api.get('/password-suggestion')).resource.string('password') ?? '';

  /// «Olvidé algo»: carné y teléfono. Devuelve la solicitud (su id se guarda
  /// en el teléfono para consultarla).
  Future<Resource> requestAccessRecovery({required bool forgotUsername, required bool forgotPassword, required String identityCard, required String phone}) async =>
      (await api.post('/guest/access-recoveries', resourceData('access-recoveries', attributes: {
        'forgotUsername': forgotUsername,
        'forgotPassword': forgotPassword,
        'identityCard': identityCard.trim(),
        'phone': phone.trim(),
      }), guest: true))
          .resource;

  /// Estado de la solicitud. Aprobada: trae `username` y/o `password` (solo
  /// lo pedido) una sola vez.
  Future<Resource> accessRecovery(String id) async => (await api.get('/guest/access-recoveries/$id', guest: true)).resource;
}
