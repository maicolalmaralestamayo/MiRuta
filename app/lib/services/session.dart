import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
import '../core/storage.dart';
import '../models/models.dart';
import 'app_pin.dart';
import 'notifications.dart';
import 'sync.dart';
import 'tracking_service.dart';
import 'user_settings.dart';

enum SessionState { loading, loggedOut, locked, ready }

/// Sesión del usuario: inicio y cierre, desbloqueo y datos propios.
class Session extends ChangeNotifier {
  static const rememberCardKey = 'security.remember_card';

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

  Future<void> login(String cardNumber, String password) async {
    final document = await api.post('/tokens', resourceData('tokens', attributes: {
      'cardNumber': cardNumber,
      'password': password,
      'deviceName': 'Android',
    }), auth: false);
    final attributes = document.resource.attributes;
    await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
    await Storage.saveLastCard(await Storage.getBool(rememberCardKey, fallback: true) ? cardNumber : null);
    await SyncService.reset();
    await _enter();
  }

  Future<void> register({required String cardNumber, required String firstName, required String lastName, required String rankId, required String password}) async {
    await api.post('/workers', resourceData('workers', attributes: {
      'cardNumber': cardNumber,
      'firstName': firstName,
      'lastName': lastName,
      'password': password,
    }, relationships: {'rank': ResourceId('ranks', rankId)}), auth: false);
    await login(cardNumber, password);
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
