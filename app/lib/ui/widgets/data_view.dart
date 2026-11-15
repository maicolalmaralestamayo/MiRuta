import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formats.dart';
import '../../core/local_cache.dart';
import '../../services/session.dart';
import 'app_scaffold.dart';
import 'common.dart';

/// Carga datos y los vuelve a cargar con el botón Actualizar o cuando GET
/// sync avisa de cambios en [kinds] (o en las huellas de los datos). Primero
/// muestra lo guardado en el teléfono («Actualizado hace …») y por detrás
/// pregunta al servidor solo si cambió (docs/11 §11.62). Sin conexión muestra
/// lo guardado con el aviso «Sin conexión: solo consulta».
class DataView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Set<String> kinds;

  /// Clave para recordar lo último cargado mientras la app está abierta.
  final String? cacheKey;

  /// Datos que mostrar si la primera carga falla (p. ej. Inicio sin conexión,
  /// con lo que ya se sabe de la persona), con el aviso de sin conexión.
  final T? fallback;

  const DataView({super.key, required this.load, required this.builder, this.kinds = const {}, this.cacheKey, this.fallback});

  @override
  State<DataView<T>> createState() => DataViewState<T>();
}

class DataViewState<T> extends State<DataView<T>> {
  static final Map<String, (Object?, DateTime)> _cache = {};

  T? _data;
  DateTime? _loadedAt;
  Object? _error;
  bool _loading = true;
  int _revision = 0;
  Session? _session;
  RefreshRegistry? _registry;

  /// Lo último cargado, si lo hay.
  T? get data => _data;

  @override
  void initState() {
    super.initState();
    final cached = widget.cacheKey == null ? null : _cache[widget.cacheKey];
    if (cached != null && cached.$1 is T) {
      _data = cached.$1 as T;
      _loadedAt = cached.$2;
    }
    _session = context.read<Session>();
    _revision = _session!.revision;
    _session!.addListener(_onSession);
    _start();
  }

  /// Primero lo guardado en el teléfono (al momento) y después, por detrás,
  /// lo que haya cambiado en el servidor (docs/11 §11.62).
  Future<void> _start() async {
    if (_data == null) {
      try {
        final trace = CacheTrace(cacheOnly: true);
        final data = await trace.run(widget.load);
        if (mounted && _data == null) {
          setState(() {
            _data = data;
            _loadedAt = trace.oldest;
          });
        }
      } catch (_) {
        // Nada guardado todavía.
      }
    }
    await reload();
  }

  void _onSession() {
    final session = _session!;
    if (session.revision == _revision) return;
    _revision = session.revision;
    if (session.lastChanged.contains('all') || session.lastChanged.contains('data') || session.lastChanged.any(widget.kinds.contains)) reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se apunta al botón Actualizar de su pantalla.
    final registry = RefreshScope.maybeOf(context);
    if (registry != _registry) {
      _registry?.remove(reload);
      _registry = registry?..add(reload);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _registry?.remove(reload);
    super.dispose();
  }

  Future<void> reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final trace = CacheTrace();
      final data = await trace.run(widget.load);
      if (!mounted) return;
      setState(() {
        _data = data;
        // Sin conexión, de cuándo es lo guardado que se muestra.
        _loadedAt = trace.offline ? (trace.oldest ?? _loadedAt) : DateTime.now();
        _error = trace.offline ? ApiException.network() : null;
        _loading = false;
      });
      if (widget.cacheKey != null) _cache[widget.cacheKey!] = (data, _loadedAt!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data ?? (_error != null ? widget.fallback : null);
    if (data == null) {
      if (_error != null) return ErrorView(message: errorText(_error), onRetry: reload);
      return const Center(child: CircularProgressIndicator());
    }
    final content = RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, reload));
    final t = Theme.of(context);
    if (_error == null) {
      final at = _loadedAt;
      // Lo guardado mientras se comprueba si cambió: «Actualizado hace …».
      if (at == null || DateTime.now().difference(at) < const Duration(minutes: 1)) return content;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            Icon(_loading ? Icons.sync : Icons.history, size: 14, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Actualizado ${agoText(at)}', style: t.textTheme.labelSmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
        Expanded(child: content),
      ]);
    }
    return Column(children: [
      Material(
        color: t.colorScheme.secondaryContainer,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.cloud_off, color: t.colorScheme.onSecondaryContainer),
          title: Text(_loadedAt == null ? errorText(_error) : 'Sin conexión: solo consulta. Actualizado ${agoText(_loadedAt)} (${formatDateTime(_loadedAt)})',
              style: TextStyle(color: t.colorScheme.onSecondaryContainer)),
          trailing: IconButton(tooltip: 'Reintentar', icon: Icon(Icons.refresh, color: t.colorScheme.onSecondaryContainer), onPressed: reload),
        ),
      ),
      Expanded(child: content),
    ]);
  }

  bool get offline => _error != null;

  bool get loading => _loading;
}
