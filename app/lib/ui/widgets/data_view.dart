import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../services/session.dart';
import 'common.dart';

/// Carga datos y los vuelve a cargar con el botón Actualizar o cuando GET
/// sync avisa de cambios en [kinds]. Sin conexión muestra lo último cargado
/// con el aviso «Sin conexión: datos del dd-mm hh:mm» (docs/11 §11.26).
class DataView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Set<String> kinds;

  /// Clave para recordar lo último cargado mientras la app está abierta.
  final String? cacheKey;

  const DataView({super.key, required this.load, required this.builder, this.kinds = const {}, this.cacheKey});

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
    reload();
  }

  void _onSession() {
    final session = _session!;
    if (session.revision == _revision) return;
    _revision = session.revision;
    if (session.lastChanged.contains('all') || session.lastChanged.any(widget.kinds.contains)) reload();
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  Future<void> reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadedAt = DateTime.now();
        _error = null;
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
    final data = _data;
    if (data == null) {
      if (_error != null) return ErrorView(message: errorText(_error), onRetry: reload);
      return const Center(child: CircularProgressIndicator());
    }
    final content = RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, reload));
    if (_error == null) return content;
    return Column(children: [
      Material(
        color: const Color(0xFFFFF3E0),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.cloud_off, color: amber),
          title: Text('Sin conexión: datos del ${formatDateTime(_loadedAt)}'),
          trailing: IconButton(tooltip: 'Reintentar', icon: const Icon(Icons.refresh), onPressed: reload),
        ),
      ),
      Expanded(child: content),
    ]);
  }

  bool get offline => _error != null;

  bool get loading => _loading;
}
