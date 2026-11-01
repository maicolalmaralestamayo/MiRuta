import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
import '../core/storage.dart';
import '../core/username.dart';
import '../models/models.dart';
import 'notifications.dart';
import 'sync.dart';
import 'tracking_service.dart';
import 'user_settings.dart';

/// locked = hay sesión, pero hay que volver a escribir la contraseña
/// ("Recordar contraseña" desactivado o pasados sus días, docs/09 §17).
enum SessionState { loading, loggedOut, locked, ready }

/// Sesión del usuario: inicio y cierre, contraseña recordada y datos propios.
class Session extends ChangeNotifier {
  /// Recordar el usuario en este teléfono (la clave conserva su nombre antiguo).
  static const rememberLoginKey = 'security.remember_card';

  /// Cuándo se escribió la contraseña por última vez en este teléfono. La
  /// contraseña nunca se guarda: se mantiene la sesión durante los días del
  /// ajuste remember_password_days.
  static const passwordEnteredAtKey = 'security.password_entered_at';

  final ApiClient api;
  SessionState state = SessionState.loading;
  Me? me;
  UserSettings settings = UserSettings({});

  /// Entidad que el Administrador está mirando (null = todas).
  Entity? adminEntity;

  Session(this.api) {
    api.onSessionExpired = () {
      if (state == SessionState.ready || state == SessionState.locked) _clear();
    };
  }

  Future<void> init() async {
    if (await Storage.refreshToken() == null) {
      state = SessionState.loggedOut;
    } else if (await needsPassword()) {
      state = SessionState.locked;
    } else {
      await _enter();
      return;
    }
    notifyListeners();
  }

  /// Inicio de sesión con usuario y contraseña.
  Future<void> login(String username, String password) async {
    final document = await api.post('/tokens', resourceData('tokens', attributes: {
      'username': Username.normalize(username),
      'password': password,
      'deviceName': 'Android',
    }), auth: false, withInstallation: true);
    await _start(document);
  }

  /// Guarda los tokens devueltos por el servidor y entra.
  Future<void> _start(JsonApiDocument document) async {
    final attributes = document.resource.attributes;
    await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
    await Storage.setString(passwordEnteredAtKey, DateTime.now().toIso8601String());
    await SyncService.reset();
    await _enter();
    await _rememberLogin();
  }

  /// Se recuerda el usuario en el teléfono (si el ajuste está activado).
  Future<void> _rememberLogin() async {
    final remember = await Storage.getBool(rememberLoginKey, fallback: true);
    await Storage.saveLastLogin(remember ? me?.username : null);
  }

  Future<void> changeUsername(String username) async {
    await api.patch('/me', resourceData('users', attributes: {'username': Username.normalize(username)}));
    await reloadMe();
    await _rememberLogin();
    notifyListeners();
  }

  /// Paso 1 del registro: crear la cuenta. La primera es la del Administrador.
  Future<void> register({required PersonName name, required String username, required String password}) async {
    await api.post('/users', resourceData('users', attributes: {
      ...nameAttributes(name),
      'username': Username.normalize(username),
      'password': password,
    }), auth: false, withInstallation: true);
    await login(username, password);
  }

  /// Paso 2 del registro: unirse a la Entidad.
  Future<void> joinEntity({required String abbreviation, required int pass, required String sex, required String rankId}) async {
    await api.post('/me/worker', resourceData('workers', attributes: {
      'entityAbbreviation': abbreviation.trim(),
      'pass': pass,
      'sex': sex,
    }, relationships: {'rank': ResourceId('ranks', rankId)}));
    await _enter();
  }

  /// "Ya me registró un superior": elige usuario y contraseña con su código.
  Future<void> activate({required String abbreviation, required int pass, required String code, required String username, required String password}) async {
    final document = await api.post('/activations', resourceData('activations', attributes: {
      'entityAbbreviation': abbreviation.trim(),
      'pass': pass,
      'code': code.trim(),
      'username': Username.normalize(username),
      'password': password,
      'deviceName': 'Android',
    }), auth: false, withInstallation: true);
    await _start(document);
  }

  /// "No puedo entrar": contraseña nueva tras la aprobación del Administrador.
  Future<void> recoverWithNewPassword(String recoveryId, String password) async {
    final document = await api.post('/guest/access-recoveries/$recoveryId/password',
        resourceData('access-recoveries', attributes: {'password': password, 'deviceName': 'Android'}),
        guest: true);
    await _start(document);
  }

  /// Contraseña nueva cuando caducó o tras recuperar el acceso. Si caducó,
  /// el servidor pide también la actual.
  Future<void> setNewPassword(String password, {String? currentPassword}) async {
    final body = resourceData('users', attributes: {'password': password});
    if (currentPassword != null) body['meta'] = {'currentPassword': currentPassword};
    await api.patch('/me', body);
    await reloadMe();
    settings = await UserSettings.refresh(api);
    notifyListeners();
    await scheduleBackgroundSync();
    SyncService.run(api).catchError((_) {});
  }

  static Map<String, dynamic> nameAttributes(PersonName name, {String prefix = ''}) {
    String key(String field) => prefix.isEmpty ? field : '$prefix${field[0].toUpperCase()}${field.substring(1)}';
    return {
      key('firstName'): name.firstName.trim(),
      // El segundo nombre es opcional (docs/09 §3): vacío se envía como null.
      key('middleName'): name.middleName.trim().isEmpty ? null : name.middleName.trim(),
      key('firstSurname'): name.firstSurname.trim(),
      key('secondSurname'): name.secondSurname.trim(),
    };
  }

  Future<void> _enter() async {
    try {
      await reloadMe();
      if (me!.mustChangePassword || me!.needsEntity) {
        // Hasta cambiar la contraseña o unirse a la Entidad, la API solo
        // permite el perfil propio.
        state = SessionState.ready;
        notifyListeners();
        return;
      }
      settings = await UserSettings.refresh(api);
    } catch (_) {
      settings = await UserSettings.cached();
      if (me == null) rethrow;
    }
    state = SessionState.ready;
    notifyListeners();
    await scheduleBackgroundSync();
    SyncService.run(api).catchError((_) {});
  }

  Future<void> reloadMe() async {
    me = Me.from((await api.get('/me', query: {'include': 'worker,worker.entity,worker.rank'})).resource);
    await SyncService.rememberMe(me!);
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    settings = await UserSettings.refresh(api);
    notifyListeners();
    await scheduleBackgroundSync();
  }

  /// Una tarea periódica por funcionalidad, cada una con la frecuencia que
  /// eligió el usuario (Android no permite menos de 15 minutos).
  Future<void> scheduleBackgroundSync() async {
    for (final part in SyncPart.values) {
      if (!settings.boolean('background_sync_enabled', true)) {
        await Workmanager().cancelByUniqueName(part.task);
        continue;
      }
      final minutes = part.hours ? settings.integer(part.setting, 24) * 60 : settings.integer(part.setting, 30);
      await Workmanager().registerPeriodicTask(
        part.task,
        part.task,
        frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    }
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      await api.delete(everywhere ? '/tokens' : '/tokens/current');
    } catch (_) {
      // Aunque falle (sin conexión), se cierra la sesión en el teléfono.
    }
    await _clear();
  }

  /// Hay que volver a escribir la contraseña: "Recordar contraseña" está
  /// desactivado o pasaron sus días (ajustes del usuario).
  Future<bool> needsPassword() async {
    final cached = await UserSettings.cached();
    if (!cached.boolean('remember_password', true)) return true;
    final raw = await Storage.getString(passwordEnteredAtKey);
    final enteredAt = raw == null ? null : DateTime.tryParse(raw);
    if (enteredAt == null) {
      // Sesiones de versiones anteriores: se empieza a contar ahora.
      await Storage.setString(passwordEnteredAtKey, DateTime.now().toIso8601String());
      return false;
    }
    return DateTime.now().difference(enteredAt) > Duration(days: cached.integer('remember_password_days', 7));
  }

  /// Pide de nuevo la contraseña (sin cerrar la sesión: los avisos siguen llegando).
  void lock() {
    if (state != SessionState.ready) return;
    state = SessionState.locked;
    notifyListeners();
  }

  Future<void> _clear() async {
    await TrackingService.stop();
    await Workmanager().cancelAll();
    await Notifications.cancelAll();
    await Storage.clearUserData();
    await Storage.setString(passwordEnteredAtKey, null);
    me = null;
    adminEntity = null;
    state = SessionState.loggedOut;
    notifyListeners();
  }
}
