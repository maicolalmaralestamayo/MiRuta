import 'dart:async';

import 'package:dio/dio.dart';

/// Ámbito de una operación del usuario contra el servidor (docs/11 §11.56):
/// mientras hay peticiones en curso dentro del ámbito, la interfaz muestra el
/// spinner que bloquea la app con el botón «Cancelar». Cancelar corta las
/// peticiones en curso y las siguientes de la misma operación.
///
/// Se transmite con una zona: todo lo que se ejecuta en [run] (también tras
/// los `await`) usa el ámbito, sin pasarlo de función en función.
class BusyScope {
  static final _key = Object();

  /// El ámbito de la operación en curso (o null, p. ej. en segundo plano).
  static BusyScope? get current => Zone.current[_key] as BusyScope?;

  final void Function(BusyScope scope) onBusyChanged;
  final CancelToken token = CancelToken();
  int _pending = 0;
  bool _closed = false;

  BusyScope({required this.onBusyChanged});

  /// El ámbito activo (no terminado) de la zona actual. Lo que quede en la
  /// zona tras terminar la operación (temporizadores, recargas) ya no lo usa.
  static BusyScope? get active {
    final scope = current;
    return scope == null || scope._closed ? null : scope;
  }

  /// Terminó la operación.
  void close() {
    _closed = true;
    _pending = 0;
  }

  /// Hay peticiones en curso.
  bool get busy => _pending > 0;

  bool get cancelled => token.isCancelled;

  /// Ejecuta [action] dentro del ámbito.
  Future<T> run<T>(Future<T> Function() action) => runZoned(action, zoneValues: {_key: this});

  void begin() {
    if (_closed) return;
    _pending++;
    if (_pending == 1) onBusyChanged(this);
  }

  void end() {
    if (_closed || _pending == 0) return;
    _pending--;
    if (_pending == 0) onBusyChanged(this);
  }

  /// «Cancelar»: corta la conexión.
  void cancel() {
    if (_closed) return;
    if (!token.isCancelled) token.cancel('Operación cancelada');
    _pending = 0;
    onBusyChanged(this);
  }
}
