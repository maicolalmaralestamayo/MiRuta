import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../navigation.dart';
import '../settings/scoped_settings_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';
import 'stops_screen.dart';

/// Tarjeta de un itinerario en Gestión: imagen, nombre, paradas y trabajadores.
class ItineraryCard extends StatelessWidget {
  final Itinerary itinerary;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ItineraryCard(this.itinerary, {super.key, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) => InfoCard(
        images: [CardImage(url: itinerary.imageUrl, icon: Icons.route)],
        title: itinerary.name,
        lines: [plural(itinerary.stopIds.length, 'parada', 'paradas'), plural(itinerary.memberCount, 'trabajador', 'trabajadores')],
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );
}

/// Itinerarios y paradas (Gestión, docs/11 §11.15): los de la Entidad
/// elegida. Crear, editar y eliminar (itineraries.manage), sus ajustes
/// (settings.itinerary) y, en su ficha, sus paradas, su orden y el recorrido
/// de referencia.
class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<List<Itinerary>>>();
  final _selection = SelectionController();
  List<Itinerary> _items = const [];

  @override
  String get entityOperation {
    final me = context.me;
    for (final op in [Op.itinerariesView, Op.itinerariesManage, Op.stopsManage, Op.settingsItinerary]) {
      if (me.canAnywhere(op)) return op;
    }
    return Op.itinerariesView;
  }

  @override
  void initState() {
    super.initState();
    initEntity();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  void onEntityChanged() {
    _selection.clear();
    _view.currentState?.reload();
  }

  Future<List<Itinerary>> _load() async {
    final items = (await context.api.getAll('/itineraries', query: {'sort': 'name', 'filter[entity]': entity!.id})).map(Itinerary.from).toList();
    _items = items;
    _selection.retain(items.map((i) => i.id));
    return items;
  }

  Future<void> _open(Itinerary itinerary) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ItineraryEditor(itinerary: itinerary)));
    _view.currentState?.reload();
  }

  Future<void> _create() async {
    final e = entity!;
    final name = await promptText(context, 'Itinerario nuevo', label: 'Nombre', required: true);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final itinerary = Itinerary.from((await context.api.post('/itineraries', resourceData('itineraries', attributes: {'name': name}, relationships: {
        'entity': ResourceId('entities', e.id),
      })))
          .resource);
      if (mounted) await _open(itinerary);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _delete() async {
    final selected = _selection.selectedOf(_items, (i) => i.id);
    final api = context.api;
    if (await runAction(context, () async {
      for (final i in selected) {
        await api.delete('/itineraries/${i.id}');
      }
    }, success: selected.length == 1 ? 'Itinerario eliminado.' : 'Itinerarios eliminados.')) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final e = entity;
    final placeholder = entityPlaceholder();
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selected = _selection.selectedOf(_items, (i) => i.id);
        return AppScaffold(
          title: 'Itinerarios y paradas',
          tab: MainTab.more,
          selection: _selection,
          actions: e == null
              ? const []
              : [
                  ActionItem(icon: Icons.add_road, label: 'Crear itinerario', enabled: me.can(Op.itinerariesManage, entityId: e.id), onPressed: _create),
                  const ActionItem.divider(),
                  ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(selected.first)),
                  ActionItem(
                    icon: Icons.tune,
                    label: 'Ajustes del itinerario',
                    needs: ActionNeeds.one,
                    enabled: selected.length == 1 && me.can(Op.settingsItinerary, entityId: e.id, itineraryId: selected.first.id),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ScopedSettingsScreen.itinerary(itineraryId: selected.first.id, name: selected.first.name))),
                  ),
                  ActionItem(
                    icon: Icons.delete_outline,
                    label: 'Eliminar',
                    needs: ActionNeeds.some,
                    destructive: true,
                    enabled: me.can(Op.itinerariesManage, entityId: e.id),
                    confirmation: '¿Eliminar los itinerarios seleccionados? Sus trabajadores se quedan sin itinerario y sin parada.',
                    onPressed: _delete,
                  ),
                ],
          body: placeholder ??
              AsyncView<List<Itinerary>>(
                key: _view,
                load: _load,
                builder: (context, items, reload) => SelectableCardList<Itinerary>(
                  controller: _selection,
                  header: [entitySelector()],
                  sections: [CardSection(title: 'Itinerarios', items: items)],
                  emptyText: 'Todavía no hay itinerarios en ${e!.abbreviation}.',
                  keyOf: (i) => i.id,
                  onOpen: _open,
                  cardBuilder: (context, i, selected, onTap, onLongPress) => ItineraryCard(i, selected: selected, onTap: onTap, onLongPress: onLongPress),
                ),
              ),
        );
      },
    );
  }
}

/// Ficha del itinerario: imagen, datos (se editan tocándolos), sus paradas
/// en orden (la primera es el punto de salida y la última, el de regreso) y
/// los recorridos de referencia. Cada cosa según su permiso.
class ItineraryEditor extends StatefulWidget {
  final Itinerary itinerary;

  const ItineraryEditor({super.key, required this.itinerary});

  @override
  State<ItineraryEditor> createState() => _ItineraryEditorState();
}

class _ItineraryEditorState extends State<ItineraryEditor> {
  late Itinerary _itinerary = widget.itinerary;
  List<ItineraryStop> _links = [];

  /// Paradas de la Entidad → en cuántos itinerarios se usa cada una.
  Map<String, int> _usage = {};

  /// Recorridos de referencia: dirección → tramo (trip-legs).
  final Map<String, Resource?> _references = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _entityId => _itinerary.entityId;

  bool _can(String op) => context.me.can(op, entityId: _entityId, itineraryId: _itinerary.id);

  Future<void> _load() async {
    try {
      final api = context.api;
      final itinerary = Itinerary.from((await api.get('/itineraries/${_itinerary.id}')).resource);
      final links = await api.getAll('/itinerary-stops', query: {'filter[itinerary]': _itinerary.id, 'include': 'stop', 'sort': 'position'});
      final all = (await api.getAll('/itineraries', query: {if (itinerary.entityId != null) 'filter[entity]': itinerary.entityId})).map(Itinerary.from);
      final usage = <String, int>{};
      for (final i in all) {
        for (final id in i.stopIds.toSet()) {
          usage[id] = (usage[id] ?? 0) + 1;
        }
      }
      final references = <String, Resource?>{};
      for (final (direction, id) in [('outbound', itinerary.referenceOutboundLegId), ('return', itinerary.referenceReturnLegId)]) {
        if (id == null) continue;
        try {
          references[direction] = (await api.get('/trip-legs/$id')).resource;
        } catch (_) {
          references[direction] = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _itinerary = itinerary;
        _links = links.map(ItineraryStop.from).toList();
        _usage = usage;
        _references
          ..clear()
          ..addAll(references);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, error);
      }
    }
  }

  Future<void> _editField(String attribute, String label, String? current) async {
    if (!_can(Op.itinerariesManage)) return;
    final value = await promptText(context, label, label: label, initial: current ?? '', required: attribute == 'name', maxLines: attribute == 'name' ? 1 : 3);
    if (value == null || !mounted) return;
    try {
      final document = await context.api.patch('/itineraries/${_itinerary.id}', resourceData('itineraries', id: _itinerary.id, attributes: {attribute: value.isEmpty ? null : value}));
      setState(() => _itinerary = Itinerary.from(document.resource));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    final link = _links[oldIndex];
    setState(() {
      _links.removeAt(oldIndex);
      _links.insert(newIndex, link);
    });
    await runAction(context, () => context.api.patch('/itinerary-stops/${link.id}', {
          'data': {'type': 'itinerary-stops', 'id': link.id, 'attributes': {'position': newIndex + 1}},
        }));
    _load();
  }

  Future<void> _link(Stop stop) => runAction(context, () => context.api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
            'itinerary': ResourceId('itineraries', _itinerary.id),
            'stop': ResourceId('stops', stop.id),
          })));

  Future<void> _addExisting() async {
    try {
      final stops = (await context.api.getAll('/stops', query: {'sort': 'landmark', if (_entityId != null) 'filter[entity]': _entityId}))
          .map(Stop.from)
          .where((s) => !_links.any((l) => l.stopId == s.id))
          .toList();
      if (!mounted) return;
      if (stops.isEmpty) {
        showMessage(context, 'No hay otras paradas. Cree una nueva.');
        return;
      }
      final stop = await pickFrom<Stop>(context, 'Añadir parada existente', stops, (s) => s.landmark, subtitle: stopAddress);
      if (stop == null || !mounted) return;
      await _link(stop);
      _load();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _createNew() async {
    final stop = await editStop(context, null, entityId: _entityId);
    if (stop == null || !mounted) return;
    await _link(stop);
    _load();
  }

  Future<void> _stopMenu(ItineraryStop link) async {
    final stop = link.stop;
    if (stop == null) return;
    final choice = await pickFrom<String>(context, stop.landmark, [
      'edit',
      if (_can(Op.settingsItinerary)) 'settings',
      if (_can(Op.itinerariesManage)) 'remove',
    ], (c) => const {
          'edit': 'Ver o editar la parada',
          'settings': 'Ajustes de la parada en este itinerario',
          'remove': 'Quitar del itinerario',
        }[c]!);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'edit':
        final saved = await editStop(context, stop, itineraryCount: _usage[stop.id] ?? 1, entityId: _entityId);
        if (saved != null) _load();
      case 'settings':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ScopedSettingsScreen.stop(itineraryStopId: link.id, name: stop.landmark)));
      case 'remove':
        if (!await confirm(context, 'Quitar parada', '¿Quitar ${stop.landmark} de este itinerario? La parada no se elimina.', accept: 'Quitar parada', destructive: true)) {
          return;
        }
        if (!mounted) return;
        await runAction(context, () => context.api.delete('/itinerary-stops/${link.id}'));
        _load();
    }
  }

  Future<void> _removeReference(String direction) async {
    final what = direction == 'outbound' ? 'referenceOutboundLeg' : 'referenceReturnLeg';
    if (!await confirm(context, 'Quitar recorrido de referencia', '¿Quitar el recorrido de referencia del ${TripLeg.directionName(direction).toLowerCase()}?',
        accept: 'Quitar recorrido', destructive: true)) {
      return;
    }
    if (!mounted) return;
    await runAction(context, () => context.api.patch('/itineraries/${_itinerary.id}', resourceData('itineraries', id: _itinerary.id, relationships: {what: null})));
    _load();
  }

  Widget _field(String label, String? value, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: InkWell(
          onTap: onTap,
          child: InputDecorator(
            isEmpty: (value ?? '').isEmpty,
            decoration: InputDecoration(labelText: label, enabled: onTap != null),
            child: (value ?? '').isEmpty ? null : Text(value!),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final manage = _can(Op.itinerariesManage);
    final order = _can(Op.itinerariesOrderStops) || manage;
    final reference = _can(Op.itinerariesReferenceRoute);
    return AppScaffold(
      title: _itinerary.name,
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.playlist_add, label: 'Añadir parada existente', enabled: manage, onPressed: _addExisting),
        ActionItem(icon: Icons.add_location_alt_outlined, label: 'Crear parada nueva', enabled: manage && context.me.can(Op.stopsManage, entityId: _entityId), onPressed: _createNew),
        ActionItem(
          icon: Icons.tune,
          label: 'Ajustes del itinerario',
          enabled: _can(Op.settingsItinerary),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScopedSettingsScreen.itinerary(itineraryId: _itinerary.id, name: _itinerary.name))),
        ),
        const ActionItem.divider(),
        ActionItem(
          icon: Icons.delete_outline,
          label: 'Eliminar',
          destructive: true,
          enabled: manage,
          confirmation: '¿Eliminar el itinerario ${_itinerary.name}? Sus trabajadores se quedan sin itinerario y sin parada.',
          onPressed: () async {
            if (await runAction(context, () => context.api.delete('/itineraries/${_itinerary.id}'), success: 'Itinerario eliminado.') && context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverList.list(children: [
                const SizedBox(height: 12),
                ImageEditor(url: _itinerary.imageUrl, icon: Icons.route, uploadPath: manage ? '/itineraries/${_itinerary.id}/image' : null, onChanged: _load),
                const SizedBox(height: 8),
                _field('Nombre', _itinerary.name, manage ? () => _editField('name', 'Nombre', _itinerary.name) : null),
                _field('Descripción', _itinerary.description, manage ? () => _editField('description', 'Descripción', _itinerary.description) : null),
                _field('Observación', _itinerary.observation, manage ? () => _editField('observation', 'Observación', _itinerary.observation) : null),
                const SectionHeader('Recorridos de referencia'),
                for (final direction in ['outbound', 'return'])
                  ListTile(
                    leading: Icon(direction == 'outbound' ? Icons.north_east : Icons.south_west),
                    title: Text(TripLeg.directionName(direction)),
                    subtitle: Text(!_references.containsKey(direction)
                        ? 'Sin recorrido de referencia'
                        : (_references[direction]?.date('startedAt') == null
                            ? 'Viaje realizado'
                            : 'Viaje realizado el ${formatDateTime(_references[direction]!.date('startedAt')!)}')),
                    onTap: _references.containsKey(direction) && reference ? () => _removeReference(direction) : null,
                  ),
                SectionHeader('Paradas (${plural(_links.length, 'parada', 'paradas')}${order ? '; arrastre para ordenarlas' : ''})'),
              ]),
              SliverReorderableList(
                itemCount: _links.length,
                onReorderItem: order ? _move : (_, _) {},
                itemBuilder: (context, i) {
                  final link = _links[i];
                  final stop = link.stop;
                  final shared = (_usage[link.stopId] ?? 1) > 1;
                  final number = CircleAvatar(child: Text('${i + 1}'));
                  return Material(
                    key: ValueKey(link.id),
                    child: ListTile(
                      leading: order ? ReorderableDragStartListener(index: i, child: number) : number,
                      title: Text(stop?.landmark ?? ''),
                      subtitle: Text([
                        if (i == 0) 'Punto de salida',
                        if (i == _links.length - 1 && i > 0) 'Punto de regreso',
                        if (stop != null) stopAddress(stop),
                        if (shared) 'En ${plural(_usage[link.stopId]!, 'itinerario', 'itinerarios')}',
                      ].join(' · ')),
                      trailing: CardImage(url: stop?.imageUrl, icon: Icons.place, size: 40),
                      onTap: () => _stopMenu(link),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ]),
    );
  }
}
