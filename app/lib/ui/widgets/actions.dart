import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'marks.dart';

/// Una acción del menú «Acciones». Solo se muestran las que se pueden usar
/// (docs/11 §11.23): cada pantalla arma la lista según lo marcado.
class ActionItem {
  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final bool destructive;
  final bool _divider;

  const ActionItem(this.icon, this.label, this.onPressed, {this.destructive = false}) : _divider = false;

  const ActionItem.divider()
      : icon = Icons.remove,
        label = '',
        onPressed = null,
        destructive = false,
        _divider = true;

  bool get isDivider => _divider;
}

/// Marcar todo / Desmarcar todo / Invertir selección (con algo marcado).
List<ActionItem> markActions(Marks marks, Iterable<String> allOfType) => [
      ActionItem(Icons.select_all, 'Marcar todo', () => marks.markAll(allOfType)),
      ActionItem(Icons.deselect, 'Desmarcar todo', marks.clear),
      ActionItem(Icons.flip, 'Invertir selección', () => marks.invert(allOfType)),
      const ActionItem.divider(),
    ];

class ActionsMenu extends StatelessWidget {
  final List<ActionItem> items;
  final void Function(ActionItem item) onSelected;

  const ActionsMenu({super.key, required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = items.toList();
    while (list.isNotEmpty && list.last.isDivider) {
      list.removeLast();
    }
    return Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 300, maxHeight: MediaQuery.of(context).size.height * 0.62),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (list.isEmpty) const ListTile(dense: true, title: Text('No hay acciones para lo marcado.')),
              for (final item in list)
                if (item.isDivider)
                  const Divider(height: 8)
                else
                  ListTile(
                    dense: true,
                    leading: Icon(item.icon, color: item.destructive ? red : t.colorScheme.primary),
                    title: Text(item.label, style: TextStyle(color: item.destructive ? red : null, fontSize: 15)),
                    onTap: () => onSelected(item),
                  ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Botón naranja «Acciones»; abierto muestra ✕.
class ActionsButton extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;

  const ActionsButton({super.key, required this.open, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: orange,
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(open ? Icons.close : Icons.more_horiz, color: Colors.black),
            const SizedBox(width: 10),
            const Text('Acciones', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Botón «Acciones» abajo a la derecha y su menú flotante, con el fondo
/// atenuado. [actions] se calcula cada vez que se abre (según lo marcado).
class ActionsOverlay extends StatefulWidget {
  final Widget child;
  final List<ActionItem> Function() actions;
  final double bottom;

  const ActionsOverlay({super.key, required this.child, required this.actions, this.bottom = 16});

  @override
  State<ActionsOverlay> createState() => _ActionsOverlayState();
}

class _ActionsOverlayState extends State<ActionsOverlay> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  /// Cada acción con el spinner de las operaciones con el servidor
  /// (docs/11 §11.56): solo se ve mientras se conecta.
  Future<void> _run(ActionItem item) async {
    setState(() => _open = false);
    final action = item.onPressed;
    if (action == null) return;
    await runAction(context, () async => await action());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: widget.child),
      if (_open) Positioned.fill(child: GestureDetector(onTap: _toggle, child: const ColoredBox(color: Colors.black38))),
      if (_open) Positioned(right: 16, bottom: widget.bottom + 68, child: ActionsMenu(items: widget.actions(), onSelected: _run)),
      Positioned(right: 16, bottom: widget.bottom, child: ActionsButton(open: _open, onPressed: _toggle)),
    ]);
  }
}
