import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import '../core/json_api.dart';
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
  Duration? _interval;

  /// La app está a la vista (no en segundo plano).
  bool _foreground = true;

  Session(this.api) {
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

  /// Sincroniza (GET sync) y avisa a las pantallas de lo que cambió.
  Future<void> sync({bool all = false}) async {
    if (state != SessionState.ready) return;
    try {
      await Storage.setForeground(_foreground);
      final result = await SyncService.run(api, foreground: _foreground);
      counters = result.counters;
      nextTrip = result.nextTrip;
      if (result.settingsChanged) settings = await AppSettings.cached();
      if (result.changed.contains('applications')) await reloadMe();
      if (all || result.changed.isNotEmpty) {
        lastChanged = all ? const {'all'} : result.changed;
        revision++;
      }
      notifyListeners();
      _schedule();
      await maybeStartTracking();
    } catch (_) {
      // Sin conexión: el punto de conexión lo indica.
    }
  }

  /// Botón Actualizar (docs/11 §11.48 y §11.56): solo las notificaciones
  /// pendientes (y los contadores); los datos los recarga la pantalla visible.
  Future<void> refresh() => sync();

  /// Consulta periódica con la app abierta: «Frecuencia día viaje» si hay
  /// un viaje ese día y «Frecuencia reposo» si no.
  void _schedule() {
    final interval = SyncService.frequency(nextTrip, settings);
    if (_timer != null && interval == _interval) return;
    _interval = interval;
    _timer?.cancel();
    // En la zona raíz: no hereda el spinner de la operación que lo programó.
    _timer = Zone.root.run(() => Timer.periodic(interval < const Duration(seconds: 30) ? const Duration(seconds: 30) : interval, (_) => sync()));
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

  /// Empieza a calcular su estado desde «Anticipación viaje» antes de la
  /// salida (docs/11 §11.41), si la ubicación está activada.
  Future<void> maybeStartTracking({bool force = false}) async {
    final trip = nextTrip;
    final person = me;
    if (trip == null || person == null || trip.itineraryId == null) return;
    if (trip.status != 'planificado' && trip.status != 'en_ejecucion') return;
    if (!force && DateTime.now().isBefore(trip.departsAt.subtract(settings.duration('anticipacion_viaje')))) return;
    final membership = person.placements.where((p) => p.itineraryId == trip.itineraryId && p.stopId != null).firstOrNull;
    if (membership == null) return;
    try {
      if (await TrackingService.runningTripId() == trip.id) return;
      if (!await TrackingService.locationReady()) return;
      final full = Trip.from((await api.get('/trips/${trip.id}', query: {'include': 'itinerary'})).resource);
      final stops = (await api.getAll('/stops', query: {'filter[itinerary]': trip.itineraryId, 'sort': 'position'})).map(Stop.from).toList();
      await TrackingService.start(trip: full, stops: stops, myStopId: membership.stopId!, settings: settings);
    } catch (_) {
      // Se intenta en la siguiente consulta.
    }
  }

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
    try {
      await TrackingService.stop();
      await Workmanager().cancelAll();
    } catch (_) {}
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
    _timer?.cancel();
    super.dispose();
  }
}
