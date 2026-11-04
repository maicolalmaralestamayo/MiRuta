import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/server_url.dart';

/// Estado de la conexión con el servidor para el punto de conexión de la
/// barra superior (docs/11 §11.14): se actualiza con cada petición y, si no
/// hay actividad, comprobando cada [interval].
class ConnectionMonitor extends ChangeNotifier {
  static const interval = Duration(seconds: 30);

  final ApiClient api;
  Timer? _timer;
  DateTime? _lastActivity;

  /// null = aún no se sabe.
  bool? online;

  /// Desde cuándo no hay conexión (para «Sin conexión con el servidor desde las hh:mm»).
  DateTime? offlineSince;

  ConnectionMonitor(this.api) {
    final previous = api.onReachability;
    api.onReachability = (reachable) {
      previous?.call(reachable);
      report(reachable);
    };
  }

  /// Dirección del servidor para mostrarla («Conectado a …»).
  String get server => ServerUrl.short(api.baseUrl);

  /// Resultado de una petición (lo llama el ApiClient).
  void report(bool reachable) {
    _lastActivity = DateTime.now();
    if (reachable) {
      offlineSince = null;
    } else {
      offlineSince ??= DateTime.now();
    }
    if (online != reachable || !reachable) {
      online = reachable;
      notifyListeners();
    }
  }

  /// Empieza a comprobar (al iniciar sesión).
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final last = _lastActivity;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await api.ping();
  }

  /// Comprueba ahora (p. ej. al tocar el punto).
  Future<void> check() => api.ping();

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
