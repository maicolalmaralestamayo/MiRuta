import 'package:flutter/material.dart';

import '../navigation.dart';
import 'actions.dart';
import 'connection_dot.dart';
import 'selection.dart';

/// La forma común de todas las pantallas con sesión (docs/11 §11.18):
/// barra superior con el título (o «N seleccionados» y ✕ en modo selección)
/// y el punto de conexión; el contenido; el botón «Acciones» con su menú
/// flotante; y, siempre abajo, la barra principal Inicio / Viajes /
/// Mensajes / Más, también en las pantallas interiores.
///
/// ```dart
/// AppScaffold(
///   title: 'Hijos',
///   selection: selection,
///   actions: [ActionItem(icon: Icons.person_add_alt_1, label: 'Crear hijo nuevo', onPressed: _create), …],
///   body: SelectableCardList<Child>(…),
/// )
/// ```
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;

  /// Acciones del botón «Acciones» (sin acciones no hay botón).
  final List<ActionItem> actions;

  /// Selección múltiple de la pantalla (barra «N seleccionados» y acciones
  /// que necesitan selección).
  final SelectionController? selection;

  /// Texto de la barra en modo selección (por defecto «N seleccionados»).
  final String Function(int count)? selectionTitle;

  /// Pestaña de la barra principal que se marca. Las pantallas interiores
  /// marcan la de la que vienen (por defecto, Inicio).
  final MainTab tab;

  /// Íconos extra de la barra superior (antes del punto de conexión).
  final List<Widget> appBarActions;

  /// Pestañas u otra barra bajo el título.
  final PreferredSizeWidget? bottom;

  /// Flecha atrás (por defecto, si hay pantalla a la que volver).
  final bool? showBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.selection,
    this.selectionTitle,
    this.tab = MainTab.home,
    this.appBarActions = const [],
    this.bottom,
    this.showBack,
  });

  /// Contenido en lista (tarjetas y secciones), con espacio abajo para el botón Acciones.
  AppScaffold.list({
    super.key,
    required this.title,
    required List<Widget> children,
    this.actions = const [],
    this.selection,
    this.selectionTitle,
    this.tab = MainTab.home,
    this.appBarActions = const [],
    this.bottom,
    this.showBack,
  }) : body = ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: children);

  static String defaultSelectionTitle(int count) => count == 1 ? '1 seleccionado' : '$count seleccionados';

  PreferredSizeWidget _appBar(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    final normal = AppBar(
      automaticallyImplyLeading: false,
      leading: canPop ? const BackButton() : null,
      title: Text(title),
      bottom: bottom,
      actions: [...appBarActions, const ConnectionDot(), const SizedBox(width: 4)],
    );
    final selection = this.selection;
    if (selection == null) return normal;
    return PreferredSize(
      preferredSize: normal.preferredSize,
      child: ListenableBuilder(
        listenable: selection,
        builder: (context, _) => selection.active
            ? AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: const Color(0xFF2A2A6E),
                leading: IconButton(tooltip: 'Salir de la selección', icon: const Icon(Icons.close), onPressed: selection.clear),
                title: Text((selectionTitle ?? defaultSelectionTitle)(selection.count)),
                bottom: bottom,
                actions: const [ConnectionDot(), SizedBox(width: 4)],
              )
            : normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget scaffold = Scaffold(
      appBar: _appBar(context),
      body: actions.isEmpty ? body : ActionsOverlay(actions: actions, selection: selection, child: body),
      bottomNavigationBar: MainNavigationBar(selected: tab),
    );
    final current = selection;
    if (current != null) {
      // Atrás en modo selección: sale de la selección.
      scaffold = ListenableBuilder(
        listenable: current,
        builder: (context, child) => PopScope(
          canPop: !current.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) current.clear();
          },
          child: child!,
        ),
        child: scaffold,
      );
    }
    return scaffold;
  }
}

/// Barra principal: Inicio, Viajes, Mensajes y Más (docs/11 §11.10: ya no
/// lleva «Solicitudes»). Desde una pantalla interior vuelve a la principal
/// y cambia de pestaña.
class MainNavigationBar extends StatelessWidget {
  final MainTab selected;

  const MainNavigationBar({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (index) => MainTabs.go(context, MainTab.values[index]),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
        NavigationDestination(icon: Icon(Icons.directions_bus_outlined), selectedIcon: Icon(Icons.directions_bus), label: 'Viajes'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Mensajes'),
        NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
      ],
    );
  }
}
