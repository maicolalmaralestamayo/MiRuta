import 'package:flutter/material.dart';

/// Selección múltiple de tarjetas (docs/11 §11.18): mantener pulsada una
/// tarjeta entra en modo selección; después cada toque marca o desmarca.
///
/// Se pasa a [SelectableCardList] (o a [SelectableCard]) y a AppScaffold,
/// que muestra la barra «N seleccionados» con ✕ y activa las acciones que
/// necesitan selección.
class SelectionController extends ChangeNotifier {
  final Set<String> _keys = {};

  Set<String> get keys => Set.unmodifiable(_keys);

  int get count => _keys.length;

  /// En modo selección (hay al menos una marcada).
  bool get active => _keys.isNotEmpty;

  bool isSelected(String key) => _keys.contains(key);

  void toggle(String key) {
    if (!_keys.remove(key)) _keys.add(key);
    notifyListeners();
  }

  void select(String key) {
    if (_keys.add(key)) notifyListeners();
  }

  void clear() {
    if (_keys.isEmpty) return;
    _keys.clear();
    notifyListeners();
  }

  /// Quita las que ya no están en la lista (tras recargarla).
  void retain(Iterable<String> existing) {
    final before = _keys.length;
    _keys.retainAll(existing.toSet());
    if (_keys.length != before) notifyListeners();
  }

  /// Los elementos seleccionados de [items].
  List<T> selectedOf<T>(Iterable<T> items, String Function(T) keyOf) => items.where((item) => _keys.contains(keyOf(item))).toList();
}

/// Envuelve una tarjeta: tocar = abrir ([onOpen]) o, en modo selección,
/// marcar/desmarcar; mantener pulsado = marcar. [builder] recibe si está
/// marcada para pasarlo a la tarjeta (`selected:`).
///
/// La tarjeta que construye debe aceptar `onTap`/`onLongPress` (todas las
/// tarjetas modelo los aceptan): se los da este widget.
class SelectableCard extends StatelessWidget {
  final SelectionController controller;
  final String selectionKey;
  final VoidCallback? onOpen;

  /// Si es false, no se puede seleccionar (solo abrir).
  final bool selectable;
  final Widget Function(BuildContext context, bool selected, VoidCallback onTap, VoidCallback? onLongPress) builder;

  const SelectableCard({super.key, required this.controller, required this.selectionKey, required this.builder, this.onOpen, this.selectable = true});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.isSelected(selectionKey);
        void tap() {
          if (controller.active) {
            if (selectable) controller.toggle(selectionKey);
          } else {
            onOpen?.call();
          }
        }

        return builder(context, selected, tap, selectable ? () => controller.toggle(selectionKey) : null);
      },
    );
  }
}

/// Grupo con título dentro de una [SelectableCardList] («Con derecho a
/// viajar», «Desactivados»…). Sin elementos y con [hideIfEmpty], no se muestra.
class CardSection<T> {
  final String? title;
  final List<T> items;
  final bool hideIfEmpty;

  /// Texto si no hay elementos (con [hideIfEmpty] false).
  final String? emptyText;

  const CardSection({this.title, required this.items, this.hideIfEmpty = true, this.emptyText});
}

/// Lista de tarjetas con selección múltiple, en secciones con título.
///
/// ```dart
/// SelectableCardList<Child>(
///   controller: selection,
///   sections: [CardSection(title: 'Con derecho a viajar', items: eligible), CardSection(title: 'Desactivados', items: inactive)],
///   keyOf: (c) => c.id,
///   onOpen: (c) => AppRoutes.openChildForm(context, c),
///   cardBuilder: (context, c, selected, onTap, onLongPress) => ChildCard(c, selected: selected, onTap: onTap, onLongPress: onLongPress),
/// )
/// ```
class SelectableCardList<T> extends StatelessWidget {
  final SelectionController controller;
  final List<CardSection<T>> sections;
  final String Function(T item) keyOf;
  final void Function(T item)? onOpen;
  final bool Function(T item)? canSelect;
  final Widget Function(BuildContext context, T item, bool selected, VoidCallback onTap, VoidCallback? onLongPress) cardBuilder;

  /// Encima de las secciones (p. ej. el selector de Entidad).
  final List<Widget> header;

  /// Texto si todas las secciones están vacías.
  final String? emptyText;

  /// Lo devuelve como `ListView` con desplazamiento propio (con false, como
  /// columna para meterla en otra lista).
  final bool scrollable;

  const SelectableCardList({
    super.key,
    required this.controller,
    required this.sections,
    required this.keyOf,
    required this.cardBuilder,
    this.onOpen,
    this.canSelect,
    this.header = const [],
    this.emptyText,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[...header];
    final empty = sections.every((s) => s.items.isEmpty);
    for (final section in sections) {
      if (section.items.isEmpty && section.hideIfEmpty) continue;
      if (section.title != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(section.title!, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary)),
        ));
      }
      if (section.items.isEmpty && section.emptyText != null) {
        children.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(section.emptyText!)));
      }
      for (final item in section.items) {
        children.add(SelectableCard(
          controller: controller,
          selectionKey: keyOf(item),
          selectable: canSelect?.call(item) ?? true,
          onOpen: onOpen == null ? null : () => onOpen!(item),
          builder: (context, selected, onTap, onLongPress) => cardBuilder(context, item, selected, onTap, onLongPress),
        ));
      }
    }
    if (empty && emptyText != null) {
      children.add(Padding(padding: const EdgeInsets.all(24), child: Text(emptyText!, textAlign: TextAlign.center)));
    }
    if (!scrollable) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    // Espacio abajo para que el botón Acciones no tape la última tarjeta.
    return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: children);
  }
}
