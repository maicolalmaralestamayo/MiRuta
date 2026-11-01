import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';
import 'stops_screen.dart';

/// Itinerarios y paradas se gestionan juntos (docs/09 §25, §26 y §32).
class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Itinerary>>>();

  Future<List<Itinerary>> _load() async => (await context.api.getAll('/itineraries', query: {'sort': 'name', ...context.entityFilter})).map(Itinerary.from).toList();

  Future<void> _create() async {
    final entity = context.entityRelationship();
    if (entity == null) return;
    final name = await promptText(context, 'Nuevo itinerario', label: 'Nombre', required: true);
    if (name == null || !mounted) return;
    try {
      final itinerary = Itinerary.from((await context.api.post('/itineraries', resourceData('itineraries', attributes: {'name': name}, relationships: entity))).resource);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ItineraryEditor(itinerary: itinerary)));
      _view.currentState?.reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Itinerarios y paradas')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nuevo itinerario')),
      body: AsyncView<List<Itinerary>>(
        key: _view,
        load: _load,
        builder: (context, itineraries, reload) => itineraries.isEmpty
            ? const EmptyView(icon: Icons.route, message: 'Todavía no hay itinerarios.')
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final itinerary in itineraries)
                  ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(itinerary.name),
                    subtitle: Text('${plural(itinerary.stopIds.length, 'parada', 'paradas')} · ${plural(itinerary.memberCount, 'miembro', 'miembros')}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ItineraryEditor(itinerary: itinerary)));
                      reload();
                    },
                  ),
              ]),
      ),
    );
  }
}

/// Ficha del itinerario: sus datos (se editan tocándolos), sus paradas en
/// orden (la primera es el punto de salida y la última, el de regreso), que
/// se añaden, crean y editan aquí mismo, y los recorridos de referencia.
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

  Future<void> _load() async {
    try {
      final api = context.api;
      final itinerary = Itinerary.from((await api.get('/itineraries/${_itinerary.id}')).resource);
      final links = await api.getAll('/itinerary-stops', query: {'filter[itinerary]': _itinerary.id, 'include': 'stop', 'sort': 'position'});
      final all = (await api.getAll('/itineraries', query: context.entityFilter)).map(Itinerary.from);
      final usage = <String, int>{};
      for (final i in all) {
        for (final id in i.stopIds.toSet()) {
          usage[id] = (usage[id] ?? 0) + 1;
        }
      }
      final references = <String, Resource?>{};
      for (final (direction, id) in [(TripDirection.outbound, itinerary.referenceOutboundLegId), (TripDirection.returning, itinerary.referenceReturnLegId)]) {
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
      if (mounted) showError(context, error);
    }
  }

  Future<void> _editField(String attribute, String label, String? current) async {
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
      final stops = (await context.api.getAll('/stops', query: {'sort': 'landmark', ...context.entityFilter}))
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
    final stop = await editStop(context, null);
    if (stop == null || !mounted) return;
    await _link(stop);
    _load();
  }

  Future<void> _editStop(ItineraryStop link) async {
    final stop = link.stop;
    if (stop == null) return;
    final saved = await editStop(context, stop, itineraryCount: _usage[stop.id] ?? 1);
    if (saved != null) _load();
  }

  Future<void> _removeReference(String direction) async {
    final what = direction == TripDirection.outbound ? 'referenceOutboundLeg' : 'referenceReturnLeg';
    if (!await confirm(context, 'Quitar recorrido de referencia', '¿Quitar el recorrido de referencia del ${TripLeg.directionName(direction).toLowerCase()}?',
        accept: 'Quitar recorrido', destructive: true)) {
      return;
    }
    if (!mounted) return;
    await runAction(context, () => context.api.patch('/itineraries/${_itinerary.id}', resourceData('itineraries', id: _itinerary.id, relationships: {what: null})));
    _load();
  }

  Widget _field(String label, String? value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: InkWell(
          onTap: onTap,
          child: InputDecorator(
            isEmpty: (value ?? '').isEmpty,
            decoration: InputDecoration(labelText: label),
            child: (value ?? '').isEmpty ? null : Text(value!),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final canManage = context.me.managesTransport;
    return Scaffold(
      appBar: AppBar(
        title: Text(_itinerary.name),
        actions: [
          if (canManage)
            DeleteButton(
              what: 'el itinerario ${_itinerary.name}',
              onDelete: () async {
                if (await runAction(context, () => context.api.delete('/itineraries/${_itinerary.id}')) && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverList.list(children: [
                const SizedBox(height: 8),
                _field('Nombre', _itinerary.name, () => _editField('name', 'Nombre', _itinerary.name)),
                _field('Descripción', _itinerary.description, () => _editField('description', 'Descripción', _itinerary.description)),
                _field('Observación', _itinerary.observation, () => _editField('observation', 'Observación', _itinerary.observation)),
                const SectionTitle('Recorridos de referencia'),
                for (final direction in [TripDirection.outbound, TripDirection.returning])
                  if (_references.containsKey(direction))
                    ListTile(
                      leading: Icon(direction == TripDirection.outbound ? Icons.north_east : Icons.south_west),
                      title: Text(TripLeg.directionName(direction)),
                      subtitle: Text(_references[direction]?.date('startedAt') == null
                          ? 'Viaje realizado'
                          : 'Viaje realizado el ${formatDateTime(_references[direction]!.date('startedAt')!)}'),
                      trailing: BusyIconButton(
                        tooltip: 'Quitar recorrido de referencia',
                        icon: const Icon(Icons.delete, color: overloadColor),
                        onPressed: () => _removeReference(direction),
                      ),
                    )
                  else
                    ListTile(
                      leading: Icon(direction == TripDirection.outbound ? Icons.north_east : Icons.south_west),
                      title: Text(TripLeg.directionName(direction)),
                      subtitle: const Text('Sin recorrido de referencia'),
                    ),
                SectionTitle('Paradas (${plural(_links.length, 'parada', 'paradas')}; arrastre para ordenarlas)'),
              ]),
              SliverReorderableList(
                itemCount: _links.length,
                onReorder: (oldIndex, newIndex) => _move(oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex),
                itemBuilder: (context, i) {
                  final link = _links[i];
                  final stop = link.stop;
                  final shared = (_usage[link.stopId] ?? 1) > 1;
                  return Material(
                    key: ValueKey(link.id),
                    child: ListTile(
                      leading: ReorderableDragStartListener(index: i, child: CircleAvatar(child: Text('${i + 1}'))),
                      title: Text(stop?.landmark ?? ''),
                      subtitle: Text([
                        if (i == 0) 'Punto de salida',
                        if (i == _links.length - 1 && i > 0) 'Punto de regreso',
                        if (stop != null) stopAddress(stop),
                        if (shared) 'En ${plural(_usage[link.stopId]!, 'itinerario', 'itinerarios')}',
                      ].join(' · ')),
                      onTap: () => _editStop(link),
                      trailing: BusyIconButton(
                        tooltip: 'Quitar del itinerario',
                        icon: const Icon(Icons.remove_circle_outline, color: overloadColor),
                        onPressed: () async {
                          if (!await confirm(context, 'Quitar parada', '¿Quitar ${stop?.landmark ?? 'la parada'} de este itinerario? La parada no se elimina.',
                              accept: 'Quitar parada', destructive: true)) {
                            return;
                          }
                          if (!context.mounted) return;
                          await runAction(context, () => context.api.delete('/itinerary-stops/${link.id}'));
                          _load();
                        },
                      ),
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(onPressed: _addExisting, icon: const Icon(Icons.playlist_add), label: const Text('Añadir parada existente')),
                    FilledButton.tonalIcon(onPressed: _createNew, icon: const Icon(Icons.add_location_alt), label: const Text('Crear parada nueva')),
                  ]),
                ),
              ),
            ]),
    );
  }
}
