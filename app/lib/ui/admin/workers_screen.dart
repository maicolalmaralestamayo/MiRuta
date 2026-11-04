import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';
import 'register_worker_screen.dart';
import 'worker_actions.dart';
import 'worker_form_screen.dart';

/// Trabajadores (Gestión, docs/11 §11.5 y §11.15): los de la Entidad elegida,
/// con su tarjeta de usuario. Tocar uno abre su ficha; manteniéndolo pulsado
/// se seleccionan varios. Acciones según los permisos en esa Entidad.
class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<List<WorkerItem>>>();
  final _selection = SelectionController();
  final _search = TextEditingController();
  List<WorkerItem> _items = const [];

  @override
  String get entityOperation => context.me.canAnywhere(Op.workersView) ? Op.workersView : Op.workersRegister;

  @override
  void initState() {
    super.initState();
    initEntity();
  }

  @override
  void dispose() {
    _selection.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void onEntityChanged() {
    _selection.clear();
    _view.currentState?.reload();
  }

  Future<List<WorkerItem>> _load() async {
    final search = _search.text.trim();
    final items = (await context.api.getAll('/workers', query: {
      'filter[entity]': entity!.id,
      'filter[active]': 'all',
      if (search.isNotEmpty) 'filter[search]': search,
      'include': WorkerItem.include,
    }))
        .map(WorkerItem.from)
        .toList();
    _items = items;
    _selection.retain(items.map((i) => i.id));
    return items;
  }

  List<Worker> get _selected => _selection.selectedOf(_items, (i) => i.id).map((i) => i.worker).toList();

  Future<void> _open(WorkerItem item) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerFormScreen(item: item, entity: entity!)));
    _view.currentState?.reload();
  }

  Future<void> _after(Future<bool> action) async {
    if (await action) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  List<ActionItem> _actions() {
    final e = entity;
    if (e == null) return const [];
    final me = context.me;
    final selected = _selection.selectedOf(_items, (i) => i.id);
    return [
      ActionItem(
        icon: Icons.person_add_alt_1,
        label: 'Registrar persona',
        enabled: me.can(Op.workersRegister, entityId: e.id),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterWorkerScreen(entity: e)));
          _view.currentState?.reload();
        },
      ),
      const ActionItem.divider(),
      ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(selected.first)),
      ActionItem(
        icon: Icons.alt_route,
        label: 'Asignar itinerario y parada',
        needs: ActionNeeds.some,
        enabled: me.canInEntity(Op.membersAssign, e.id),
        onPressed: () => _after(assignItineraryAndStop(context, _selected, e)),
      ),
      ActionItem(
        icon: Icons.add_moderator_outlined,
        label: 'Asignar rol',
        needs: ActionNeeds.some,
        enabled: me.can(Op.rolesAssign, entityId: e.id),
        onPressed: () => _after(assignRole(context, _selected, e)),
      ),
      ActionItem(
        icon: Icons.toggle_off_outlined,
        label: 'Desactivar',
        needs: ActionNeeds.some,
        enabled: me.can(Op.workersDeactivate, entityId: e.id) && selected.every((i) => i.worker.active),
        confirmation: '¿Desactivar a los trabajadores seleccionados? Conservan su itinerario, su parada y sus roles.',
        onPressed: () => _after(setWorkersActive(context, _selected, false)),
      ),
      ActionItem(
        icon: Icons.toggle_on_outlined,
        label: 'Reactivar',
        needs: ActionNeeds.some,
        enabled: me.can(Op.workersDeactivate, entityId: e.id) && selected.every((i) => !i.worker.active),
        onPressed: () => _after(setWorkersActive(context, _selected, true)),
      ),
      ActionItem(
        icon: Icons.logout,
        label: 'Dar de baja de la Entidad',
        needs: ActionNeeds.some,
        destructive: true,
        enabled: me.can(Op.entitiesAssignMembers, entityId: e.id) && selected.every((i) => i.worker.active),
        confirmation: 'Perderán su itinerario, su parada y sus roles en ${e.abbreviation}. Para volver tendrán que solicitarlo de nuevo. ¿Darlos de baja?',
        onPressed: () => _after(removeFromEntity(context, _selected)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = entityPlaceholder();
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => AppScaffold(
        title: 'Trabajadores',
        tab: MainTab.more,
        selection: _selection,
        actions: _actions(),
        body: placeholder ??
            AsyncView<List<WorkerItem>>(
              key: _view,
              load: _load,
              builder: (context, items, reload) => SelectableCardList<WorkerItem>(
                controller: _selection,
                header: [
                  entitySelector(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar por nombre, usuario o carné',
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Borrar la búsqueda',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  reload();
                                },
                              ),
                      ),
                      onSubmitted: (_) => reload(),
                    ),
                  ),
                ],
                sections: [
                  CardSection(title: 'Activos', items: items.where((i) => i.worker.active).toList()),
                  CardSection(title: 'Desactivados', items: items.where((i) => !i.worker.active).toList()),
                ],
                emptyText: _search.text.trim().isEmpty ? 'No hay trabajadores en ${entity!.abbreviation}.' : 'Nadie coincide con la búsqueda.',
                keyOf: (i) => i.id,
                onOpen: _open,
                cardBuilder: (context, i, selected, onTap, onLongPress) => UserCard(
                  fullName: i.worker.fullName,
                  photoUrl: i.worker.photoUrl,
                  entities: i.entities,
                  dim: !i.worker.active,
                  selected: selected,
                  onTap: onTap,
                  onLongPress: onLongPress,
                ),
              ),
            ),
      ),
    );
  }
}
