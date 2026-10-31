import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
import '../core/storage.dart';
import '../core/username.dart';
import '../models/models.dart';
import 'app_pin.dart';
import 'notifications.dart';
import 'sync.dart';
import 'tracking_service.dart';
import 'user_settings.dart';

enum SessionState { loading, loggedOut, locked, ready }

/// Sesión del usuario: inicio y cierre, desbloqueo y datos propios.
class Session extends ChangeNotifier {
  /// Recordar el usuario en este teléfono (la clave conserva su nombre antiguo).
  static const rememberLoginKey = 'security.remember_card';

  /// Entró con el carné: hay que decirle cuál es su usuario.
  bool showUsernameHint = false;

  final ApiClient api;
  SessionState state = SessionState.loading;
  Worker? me;
  UserSettings settings = UserSettings({});

  Session(this.api) {
    api.onSessionExpired = () {
      if (state == SessionState.ready || state == SessionState.locked) _clear();
    };
  }

  Future<void> init() async {
    if (await Storage.refreshToken() == null) {
      state = SessionState.loggedOut;
    } else if (await AppPin.isEnabled()) {
      state = SessionState.locked;
    } else {
      await _enter();
      return;
    }
    notifyListeners();
  }

  /// Inicio de sesión con el usuario o, como alternativa, con el carné.
  Future<void> login(String login, String password) async {
    final document = await api.post('/tokens', resourceData('tokens', attributes: {
      'username': login.trim(),
      'password': password,
      'deviceName': 'Android',
    }), auth: false);
    final attributes = document.resource.attributes;
    await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
    showUsernameHint = Username.isCardNumber(login);
    await SyncService.reset();
    await _enter();
    await _rememberLogin();
  }

  /// Se recuerda el usuario, aunque haya entrado con el carné.
  Future<void> _rememberLogin() async {
    final remember = await Storage.getBool(rememberLoginKey, fallback: true);
    await Storage.saveLastLogin(remember ? me?.username : null);
  }

  Future<void> changeUsername(String username) async {
    await api.patch('/me', resourceData('workers', attributes: {'username': Username.normalize(username)}));
    await reloadMe();
    await _rememberLogin();
    notifyListeners();
  }

  /// Entrar con el código de restablecimiento que envió el Administrador.
  /// Después la app obliga a elegir una contraseña nueva.
  Future<void> loginWithResetCode(String login, String code) async {
    final document = await api.post('/tokens/reset-code', resourceData('tokens', attributes: {
      'username': login.trim(),
      'resetCode': code,
      'deviceName': 'Android',
    }), auth: false);
    final attributes = document.resource.attributes;
    await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
    await SyncService.reset();
    await _enter();
  }

  /// Contraseña nueva tras entrar con un código (no pide la actual).
  Future<void> setNewPassword(String password) async {
    await api.patch('/me', resourceData('workers', attributes: {'password': password}));
    await reloadMe();
    settings = await UserSettings.refresh(api);
    notifyListeners();
    await scheduleBackgroundSync();
    SyncService.run(api).catchError((_) {});
  }

  Future<void> register({required String cardNumber, required String username, required String firstName, required String lastName, required String rankId, required String password}) async {
    await api.post('/workers', resourceData('workers', attributes: {
      'cardNumber': cardNumber,
      'username': Username.normalize(username),
      'firstName': firstName,
      'lastName': lastName,
      'password': password,
    }, relationships: {'rank': ResourceId('ranks', rankId)}), auth: false);
    await login(username, password);
  }

  /// Desbloqueo con el PIN de la app.
  Future<bool> unlock(String pin) async {
    final ok = await AppPin.verify(pin);
    if (ok) {
      if (me == null) {
        await _enter();
      } else {
        state = SessionState.ready;
        notifyListeners();
      }
    }
    return ok;
  }

  /// Vuelve a pedir el PIN (al volver a la app tras un rato fuera).
  Future<void> lock() async {
    if (state == SessionState.ready && await AppPin.isEnabled()) {
      state = SessionState.locked;
      notifyListeners();
    }
  }

  Future<void> _enter() async {
    try {
      await reloadMe();
      if (me!.mustChangePassword) {
        // Hasta cambiar la contraseña, la API solo permite el perfil propio.
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
    me = Worker.from((await api.get('/me', query: {'include': 'rank'})).resource);
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
      final minutes = settings.integer(part.setting, 30);
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

  Future<void> _clear() async {
    await TrackingService.stop();
    await Workmanager().cancelAll();
    await Notifications.cancelAll();
    await AppPin.remove();
    await Storage.clearUserData();
    me = null;
    state = SessionState.loggedOut;
    notifyListeners();
  }
}
