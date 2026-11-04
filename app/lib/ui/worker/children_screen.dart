import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api/children_api.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'worker_common.dart';

/// Hijos (docs/11 §11.11 y §11.18; maqueta pantallas-final.png, 3):
/// «Con derecho a viajar» y «Desactivados» (en gris). Los que perdieron el
/// derecho por edad dejan de mostrarse.
///
/// Acciones: Crear hijo nuevo, Agregar hijo ya registrado (por carné),
/// Editar (uno), Desactivar / Reactivar y Eliminar (uno o varios).
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final _selection = SelectionController();
  final _view = GlobalKey<AsyncViewState<List<Child>>>();
  List<Child> _children = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<Child>> _load() async {
    final children = await ChildrenApi(context.api).mine(context.me.id);
    _children = children;
    _selection.retain(children.map((c) => c.id));
    return children;
  }

  Future<void> _reload() async {
    _selection.clear();
    await _view.currentState?.reload();
  }

  List<Child> get _selected => _selection.selectedOf(_children, (c) => c.id);

  Future<void> _open(Future<void> Function() route) async {
    await route();
    if (mounted) await _reload();
  }

  /// Desactiva los seleccionados si hay alguno activo; si no, los reactiva.
  bool get _deactivating => _selected.any((c) => c.active);

  Future<void> _toggleActive() async {
    final api = ChildrenApi(context.api);
    final activate = !_deactivating;
    for (final child in _selected) {
      if (child.active != activate) await api.setActive(child.id, activate);
    }
    if (!mounted) return;
    showMessage(context, activate ? 'Hijos reactivados' : 'Hijos desactivados');
    await _reload();
  }

  Future<void> _remove() async {
    final api = ChildrenApi(context.api);
    for (final child in _selected) {
      await api.remove(child.id);
    }
    if (!mounted) return;
    showMessage(context, 'Hijos quitados');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final deactivating = _selected.isEmpty || _deactivating;
        return AppScaffold(
          title: 'Hijos',
          selection: _selection,
          actions: [
            ActionItem(icon: Icons.person_add_alt_1, label: 'Crear hijo nuevo', onPressed: () => _open(() => AppRoutes.childForm(context))),
            ActionItem(icon: Icons.link, label: 'Agregar hijo ya registrado', onPressed: () => _open(() => AppRoutes.addRegisteredChild(context))),
            const ActionItem.divider(),
            ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(() => AppRoutes.childForm(context, _selected.first))),
            ActionItem(
              icon: deactivating ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
              label: deactivating ? 'Desactivar' : 'Reactivar',
              needs: ActionNeeds.some,
              confirmation: deactivating
                  ? '¿Desactivar los hijos seleccionados? Dejarán de mostrarse en Inicio y no podrá marcarlos al subir.'
                  : '¿Reactivar los hijos seleccionados?',
              onPressed: _toggleActive,
            ),
            ActionItem(
              icon: Icons.delete_outline,
              label: 'Eliminar',
              needs: ActionNeeds.some,
              destructive: true,
              confirmation: '¿Quitar los hijos seleccionados? Si otra persona también los tiene declarados, seguirán siendo hijos de ella.',
              onPressed: _remove,
            ),
          ],
          body: AsyncView<List<Child>>(
            key: _view,
            load: _load,
            builder: (context, children, reload) {
              final eligible = children.where((c) => c.travels).toList();
              final inactive = children.where((c) => !c.active).toList();
              return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
                SelectableCardList<Child>(
                  controller: _selection,
                  scrollable: false,
                  sections: [
                    CardSection(title: 'Con derecho a viajar', items: eligible),
                    CardSection(title: 'Desactivados', items: inactive),
                  ],
                  keyOf: (c) => c.id,
                  emptyText: 'No tiene hijos declarados.\nUse «Acciones» para crear uno nuevo o agregar uno ya registrado.',
                  onOpen: (c) => _open(() => AppRoutes.childForm(context, c)),
                  cardBuilder: (context, c, selected, onTap, onLongPress) => ChildCard(c, selected: selected, onTap: onTap, onLongPress: onLongPress),
                ),
                const DeveloperChatFooter(),
              ]);
            },
          ),
        );
      },
    );
  }
}
