import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../navigation.dart';
import 'actions.dart';
import 'common.dart';
import 'connection_dot.dart';
import 'marks.dart';

/// Lo que recarga el botón Actualizar de una pantalla (docs/11 §11.56: solo
/// los datos de la pantalla visible). Las DataView de la pantalla se
/// registran solas; [AppScaffold.onRefresh] añade lo demás.
class RefreshRegistry {
  final Set<Future<void> Function()> _loaders = {};

  void add(Future<void> Function() loader) => _loaders.add(loader);

  void remove(Future<void> Function() loader) => _loaders.remove(loader);

  Future<void> reloadAll() async {
    await Future.wait([for (final loader in _loaders.toList()) loader().catchError((_) {})]);
  }
}

class RefreshScope extends InheritedWidget {
  final RefreshRegistry registry;

  const RefreshScope({super.key, required this.registry, required super.child});

  static RefreshRegistry? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<RefreshScope>()?.registry;

  @override
  bool updateShouldNotify(RefreshScope oldWidget) => registry != oldWidget.registry;
}

/// Forma común de las pantallas con sesión (docs/11 §11.48 y maquetas G18):
/// barra con el título, el botón Actualizar y el punto de conexión (o «N
/// marcadas» con ✕); el contenido; el botón «Acciones»; y la barra principal.
class AppScaffold extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<ActionItem> Function()? actions;
  final Marks? marks;
  final MainTab tab;
  final Widget? bottom;
  final Color? background;

  /// Recarga de la pantalla con el botón Actualizar (además de sus DataView).
  final Future<void> Function()? onRefresh;

  const AppScaffold({super.key, required this.title, this.subtitle, required this.body, this.actions, this.marks, this.tab = MainTab.home, this.bottom, this.background, this.onRefresh});

  /// Contenido en lista, con espacio abajo para el botón Acciones.
  AppScaffold.list({super.key, required this.title, this.subtitle, required List<Widget> children, this.actions, this.marks, this.tab = MainTab.home, this.bottom, this.background, this.onRefresh})
      : body = ListView(padding: const EdgeInsets.only(top: 4, bottom: 120), children: children);

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  final _registry = RefreshRegistry();

  String get title => widget.title;
  String? get subtitle => widget.subtitle;
  Widget get body => widget.body;
  List<ActionItem> Function()? get actions => widget.actions;
  Marks? get marks => widget.marks;
  MainTab get tab => widget.tab;
  Widget? get bottom => widget.bottom;
  Color? get background => widget.background;

  Future<void> _refresh() async {
    await _registry.reloadAll();
    await widget.onRefresh?.call();
  }

  PreferredSizeWidget _appBar(BuildContext context, bool ready) {
    final canPop = Navigator.of(context).canPop();
    final normal = AppBar(
      automaticallyImplyLeading: false,
      leading: canPop ? const BackButton() : null,
      title: subtitle == null
          ? Text(title)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.white))]),
      actions: [if (ready) RefreshButton(onRefresh: _refresh), const ConnectionDot(), const SizedBox(width: 4)],
    );
    final m = marks;
    if (m == null) return normal;
    return PreferredSize(
      preferredSize: normal.preferredSize,
      child: ListenableBuilder(
        listenable: m,
        builder: (context, _) => m.active
            ? AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: const Color(0xFF2A2A6E),
                leading: IconButton(tooltip: 'Desmarcar todo', icon: const Icon(Icons.close), onPressed: m.clear),
                title: Text(m.count == 1 ? '1 marcada' : '${m.count} marcadas'),
                actions: const [ConnectionDot(), SizedBox(width: 4)],
              )
            : normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = actions == null ? body : ActionsOverlay(actions: actions!, child: body);
    if (bottom != null) content = Column(children: [Expanded(child: content), bottom!]);
    final ready = context.select<Session, bool>((s) => s.state == SessionState.ready);
    Widget scaffold = Scaffold(
      backgroundColor: background,
      appBar: _appBar(context, ready),
      body: RefreshScope(registry: _registry, child: content),
      bottomNavigationBar: ready ? MainNavigationBar(selected: tab) : null,
    );
    final m = marks;
    if (m != null) {
      scaffold = ListenableBuilder(
        listenable: m,
        builder: (context, child) => PopScope(
          canPop: !m.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) m.clear();
          },
          child: child!,
        ),
        child: scaffold,
      );
    }
    return scaffold;
  }
}

/// Botón Actualizar de la barra (docs/11 §11.48 y §11.56): solo las
/// notificaciones pendientes y los datos de la pantalla visible.
class RefreshButton extends StatefulWidget {
  final Future<void> Function()? onRefresh;

  const RefreshButton({super.key, this.onRefresh});

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Actualizar',
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await context.read<Session>().refresh();
                await widget.onRefresh?.call();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy ? const BusyIndicator(size: 18, color: Colors.white) : const Icon(Icons.refresh, color: Colors.white),
    );
  }
}

/// Barra principal con el número de solicitudes en Gestión.
class MainNavigationBar extends StatelessWidget {
  final MainTab selected;

  const MainNavigationBar({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final badge = context.select<Session, int>((s) => s.managementBadge);
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (index) => MainTabs.go(context, MainTab.values[index]),
      destinations: [
        const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
        NavigationDestination(
          icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.settings_outlined)),
          selectedIcon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.settings)),
          label: 'Gestión',
        ),
        const NavigationDestination(icon: Icon(Icons.directions_bus_outlined), selectedIcon: Icon(Icons.directions_bus), label: 'Viajes'),
        const NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
      ],
    );
  }
}
