import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:miruta_alarm/miruta_alarm.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
import '../core/local_cache.dart';
import '../core/storage.dart';
import '../core/username.dart';
import '../models/models.dart';
import 'app_settings.dart';
import 'app_updates.dart';
import 'connection.dart';
import 'notifications.dart';
import 'qr/qr_device.dart';
import 'qr/qr_queue.dart';
import 'sync.dart';
import 'tracking/tracking_service.dart';
import 'tracking/trip_window.dart';

enum SessionState { loading, loggedOut, ready }

/// Sesión del usuario: inicio y cierre, sus datos, ajustes de la app,
/// sincronización mientras está abierta y actualización obligatoria.
class Session extends ChangeNotifier {
  /// «Recordar contraseña»: sin marcarlo, al volver a abrir la app se pide otra vez.
  static const rememberKey = 'security.remember_password';

  final ApiClient api;
  late final ConnectionMonitor connection = ConnectionMonitor(api);
  SessionState state = SessionState.loading;
  Me? me;
  AppSettings settings = const AppSettings({});
  Map<String, int> counters = const {};
  NextTrip? nextTrip;

  /// Aumenta cada vez que hay que recargar los datos de las pantallas
  /// (botón Actualizar o cambios que avisa GET sync en [lastChanged]).
  int revision = 0;
  Set<String> lastChanged = const {};

  /// Se cerró la sesión por una actualización obligatoria (la pantalla de
  /// inicio de sesión lo muestra).
  bool updateRequired = false;

  Timer? _timer;

  /// La app está a la vista (no en segundo plano).
  bool _foreground = true;

  Session(this.api) {
    try {
      FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    } catch (_) {}
    api.onSessionExpired = () {
      if (state == SessionState.ready) _clear();
    };
    api.onUpdateRequired = (meta) => _onUpdateRequired(meta);
  }

  /// Número de la pestaña Gestión: solicitudes por resolver (Administrador y
  /// Jefe). Las propias resueltas se ven en Inicio.
  int get managementBadge => (me?.manages ?? false) ? (counters['applicationsToResolve'] ?? 0) : 0;

  Future<void> init() async {
    settings = await AppSettings.cached();
    if (await AppUpdates.mandatory() != null) updateRequired = true;
    if (await Storage.refreshToken() == null || updateRequired || !await Storage.getBool(rememberKey, fallback: true)) {
      if (await Storage.refreshToken() != null) await _clear(notify: false);
      state = SessionState.loggedOut;
      notifyListeners();
      return;
    }
    try {
      await _enter();
    } catch (_) {
      if (state != SessionState.ready) {
        state = SessionState.loggedOut;
        notifyListeners();
      }
    }
  }

  Future<void> login(String username, String password, {bool remember = true}) async {
    final document = await api.post('/tokens', resourceData('tokens', attributes: {
      'username': Username.normalize(username),
      'password': password,
      'deviceName': 'Android',
    }), auth: false, withInstallation: true);
    final attributes = document.resource.attributes;
    await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
    await Storage.setBool(rememberKey, remember);
    await Storage.saveLastLogin(Username.normalize(username));
    updateRequired = false;
    await _enter();
  }

  Future<void> register({required PersonName name, required String identityCard, required String username, required String password}) async {
    await api.post('/users', resourceData('users', attributes: {
      ...name.toAttributes(),
      'identityCard': identityCard.trim(),
      'username': Username.normalize(username),
      'password': password,
    }), auth: false, withInstallation: true);
    await login(username, password);
  }

  Future<void> _enter() async {
    try {
      await reloadMe();
    } catch (_) {
      final cached = await Storage.getJson(SyncService.meKey);
      if (cached['userId'] == null) rethrow;
    }
    if (me == null) throw StateError('Sin datos de la persona');
    state = SessionState.ready;
    counters = await SyncService.cachedCounters();
    nextTrip = await SyncService.cachedNextTrip();
    notifyListeners();
    connection.start();
    if (me!.mustChangePassword) return;
    unawaited(_afterEnter());
  }

  Future<void> _afterEnter() async {
    try {
      settings = (await AppSettings.refresh(api)).$1;
    } catch (_) {}
    await sync();
    QrDevice.ensureCertificate(api, me!.userId).then((_) {}, onError: (_) {});
    if (me!.manages) QrQueue.refreshServerKey(api).catchError((_) {});
  }

  Future<void> reloadMe() async {
    me = Me.from((await api.get('/me')).resource);
    await Storage.setJson(SyncService.meKey, me!.toJson());
    notifyListeners();
  }

  /// Sincroniza (GET sync) y avisa a las pantallas de lo que cambió. Con el
  /// servicio de la ventana de viaje activo, la petición la hace él (una sola
  /// cada Z, docs/11 §11.62): aquí solo se le pide que conecte ya.
  Future<void> sync({bool all = false, bool now = false}) async {
    if (state != SessionState.ready) return;
    try {
      await Storage.setForeground(_foreground);
      if (await TrackingService.isRunning) {
        if (now) TrackingService.syncNow();
        _schedule();
        return;
      }
      final result = await SyncService.run(api, foreground: _foreground);
      _apply(result.changed, all: all);
      counters = result.counters;
      nextTrip = result.nextTrip;
      if (result.settingsChanged) settings = await AppSettings.cached();
      notifyListeners();
      await TripWindow.reschedule(settings, foreground: _foreground);
    } catch (_) {
      // Sin conexión: el punto de conexión lo indica.
    }
    _schedule();
  }

  void _apply(Set<String> changed, {bool all = false}) {
    if (changed.contains('applications') || changed.contains('workers')) reloadMe().catchError((_) {});
    if (all || changed.isNotEmpty) {
      lastChanged = all ? const {'all'} : changed;
      revision++;
    }
  }

  /// Lo que envía el servicio del viaje tras cada petición (con la app abierta).
  void _onServiceData(Object data) {
    if (data is! Map) return;
    final next = DateTime.tryParse('${data['nextAt'] ?? ''}');
    if (next != null) TripWindow.nextContact.value = next;
    // Tocó «Mi estado» (la notificación del servicio): la pantalla principal lo atiende.
    final tap = data['tap'];
    if (tap is String && tap.isNotEmpty) {
      Storage.setString(TrackingService.tapKey, null);
      Notifications.tapped.value = tap;
    }
    final changed = (data['changed'] as List?)?.map((e) => '$e').toSet();
    if (changed != null) {
      SyncService.cachedCounters().then((c) {
        counters = c;
        _apply(changed);
        notifyListeners();
      });
    }
  }

  /// Botón Actualizar (docs/11 §11.48 y §11.56): solo las notificaciones
  /// pendientes (y los contadores); los datos los recarga la pantalla visible.
  /// Conecta ya y reinicia el contador.
  Future<void> refresh() => sync(now: true);

  /// Próxima consulta con la app abierta (docs/11 §11.62): dentro de la
  /// ventana de viaje cada Z; fuera, cada F. El contador de la barra la muestra.
  Future<void> _schedule() async {
    _timer?.cancel();
    _timer = null;
    if (state != SessionState.ready || !_foreground) return;
    final open = await TripWindow.open(settings: settings);
    final interval = open != null ? settings.windowEvery : settings.outsideEvery;
    if (await TrackingService.isRunning) {
      // La conexión la hace el servicio: el contador sigue su ritmo.
      await Storage.setForeground(true);
      final current = TripWindow.nextContact.value;
      if (current == null || current.isBefore(DateTime.now())) TripWindow.nextContact.value = DateTime.now().add(interval);
      _timer = Zone.root.run(() => Timer(interval + const Duration(seconds: 2), () => _schedule()));
      return;
    }
    TripWindow.nextContact.value = DateTime.now().add(interval);
    // En la zona raíz: no hereda el spinner de la operación que lo programó.
    _timer = Zone.root.run(() => Timer(interval, () => sync()));
  }

  void pause() {
    _foreground = false;
    Storage.setForeground(false);
    _timer?.cancel();
    _timer = null;
    connection.stop();
  }

  void resume() {
    _foreground = true;
    if (state != SessionState.ready) return;
    connection.start();
    sync();
  }

  /// Abre la ventana de viaje si toca (con la app a la vista).
  Future<void> maybeStartTracking() => TripWindow.reschedule(settings, foreground: _foreground);

  void _onUpdateRequired(Map<String, dynamic> meta) {
    if (updateRequired && state == SessionState.loggedOut) return;
    updateRequired = true;
    AppUpdates.rememberMandatory(meta).then((_) async {
      if (state == SessionState.ready) {
        try {
          await api.delete('/tokens/current');
        } catch (_) {}
        await _clear();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> logout() async {
    try {
      await api.delete('/tokens/current');
    } catch (_) {
      // Aunque falle (sin conexión), se cierra la sesión en el teléfono.
    }
    await _clear();
  }

  Future<void> _clear({bool notify = true}) async {
    _timer?.cancel();
    _timer = null;
    TripWindow.nextContact.value = null;
    try {
      await TrackingService.stop();
      await MirutaAlarm.cancel();
      await Workmanager().cancelAll();
    } catch (_) {}
    // La caché local se borra al cerrar sesión (docs/11 §11.62).
    await LocalCache.clear();
    try {
      await Notifications.cancelAll();
    } catch (_) {}
    await Storage.clearUserData();
    connection.stop();
    me = null;
    counters = const {};
    nextTrip = null;
    state = SessionState.loggedOut;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    try {
      FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    } catch (_) {}
    _timer?.cancel();
    super.dispose();
  }
}
