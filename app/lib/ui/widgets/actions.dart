import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'selection.dart';

/// Qué selección necesita una acción para estar activa (docs/11 §11.18).
enum ActionNeeds {
  /// Siempre activa (Crear, Agregar, Solicitar, Declarar, Guardar…).
  none,

  /// Exactamente una tarjeta seleccionada (Editar).
  one,

  /// Una o varias (Desactivar, Eliminar, Darme de baja, Cancelar solicitud…).
  some,
}

/// Una acción del menú «Acciones».
class ActionItem {
  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final ActionNeeds needs;

  /// false = en gris aunque la selección valga (p. ej. «Darme de baja» con la
  /// tarjeta «Trabajador» seleccionada).
  final bool enabled;

  /// En rojo (Eliminar).
  final bool destructive;

  /// Si se indica, se pide confirmación con este texto antes de hacerla.
  final String? confirmation;
  final bool _divider;

  const ActionItem({
    required this.icon,
    required this.label,
    this.onPressed,
    this.needs = ActionNeeds.none,
    this.enabled = true,
    this.destructive = false,
    this.confirmation,
  }) : _divider = false;

  /// Separador entre grupos de acciones.
  const ActionItem.divider()
      : icon = Icons.remove,
        label = '',
        onPressed = null,
        needs = ActionNeeds.none,
        enabled = false,
        destructive = false,
        confirmation = null,
        _divider = true;

  bool get isDivider => _divider;

  /// Activa con [selected] tarjetas seleccionadas.
  bool isEnabled(int selected) {
    if (!enabled || onPressed == null) return false;
    return switch (needs) {
      ActionNeeds.none => true,
      ActionNeeds.one => selected == 1,
      ActionNeeds.some => selected >= 1,
    };
  }
}

/// Menú flotante de acciones (ícono y texto; en gris las que no aplican;
/// Eliminar en rojo).
class ActionsMenu extends StatelessWidget {
  final List<ActionItem> items;
  final int selectedCount;
  final void Function(ActionItem item) onSelected;

  const ActionsMenu({super.key, required this.items, this.selectedCount = 0, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 280, maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final item in items)
                if (item.isDivider)
                  const Divider(height: 8)
                else
                  Builder(builder: (context) {
                    final enabled = item.isEnabled(selectedCount);
                    final color = enabled ? (item.destructive ? overloadColor : null) : t.disabledColor;
                    return ListTile(
                      dense: true,
                      enabled: enabled,
                      leading: Icon(item.icon, color: enabled ? (item.destructive ? overloadColor : t.colorScheme.primary) : t.disabledColor),
                      title: Text(item.label, style: TextStyle(color: color, fontSize: 15)),
                      onTap: enabled ? () => onSelected(item) : null,
                    );
                  }),
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

/// Pone el botón «Acciones» abajo a la derecha de [child] y, al tocarlo, el
/// menú flotante encima, con el fondo atenuado. AppScaffold ya lo usa: solo
/// hace falta usarlo directamente en una pantalla que no use AppScaffold.
class ActionsOverlay extends StatefulWidget {
  final Widget child;
  final List<ActionItem> actions;
  final SelectionController? selection;

  const ActionsOverlay({super.key, required this.child, required this.actions, this.selection});

  @override
  State<ActionsOverlay> createState() => _ActionsOverlayState();
}

class _ActionsOverlayState extends State<ActionsOverlay> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  Future<void> _run(ActionItem item) async {
    setState(() => _open = false);
    if (item.confirmation != null) {
      final ok = await confirm(context, item.label, item.confirmation!, accept: item.label, destructive: item.destructive);
      if (!ok || !mounted) return;
    }
    try {
      await item.onPressed!();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    final selection = widget.selection;
    Widget menu() => ActionsMenu(items: widget.actions, selectedCount: selection?.count ?? 0, onSelected: _run);
    return Stack(children: [
      Positioned.fill(child: widget.child),
      if (_open) Positioned.fill(child: GestureDetector(onTap: _toggle, child: const ColoredBox(color: Colors.black38))),
      if (_open)
        Positioned(
          right: 16,
          bottom: 84,
          child: selection == null ? menu() : ListenableBuilder(listenable: selection, builder: (context, _) => menu()),
        ),
      Positioned(right: 16, bottom: 16, child: ActionsButton(open: _open, onPressed: _toggle)),
    ]);
  }
}
