import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import 'stops_screen.dart';

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
      appBar: AppBar(title: const Text('Itinerarios')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Itinerario')),
      body: AsyncView<List<Itinerary>>(
        key: _view,
        load: _load,
        builder: (context, itineraries, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final itinerary in itineraries)
            ListTile(
              leading: const Icon(Icons.route),
              title: Text(itinerary.name),
              subtitle: Text('${itinerary.stopIds.length} paradas · ${itinerary.memberCount} miembros'),
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

/// Datos del itinerario y orden de sus paradas (la primera es el punto de
/// salida y la última, el de regreso).
class ItineraryEditor extends StatefulWidget {
  final Itinerary itinerary;

  const ItineraryEditor({super.key, required this.itinerary});

  @override
  State<ItineraryEditor> createState() => _ItineraryEditorState();
}

class _ItineraryEditorState extends State<ItineraryEditor> {
  late Itinerary _itinerary = widget.itinerary;
  List<ItineraryStop> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final links = await context.api.getAll('/itinerary-stops', query: {'filter[itinerary]': _itinerary.id, 'include': 'stop', 'sort': 'position'});
      setState(() {
        _links = links.map(ItineraryStop.from).toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _editField(String attribute, String label, String? current) async {
    final value = await promptText(context, label, initial: current ?? '', required: attribute == 'name', maxLines: attribute == 'name' ? 1 : 3);
    if (value == null || !mounted) return;
    try {
      final document = await context.api.patch('/itineraries/${_itinerary.id}', resourceData('itineraries', id: _itinerary.id, attributes: {attribute: value}));
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

  Future<void> _add() async {
    final choice = await pickFrom<String>(context, 'Añadir parada', ['existing', 'new'], (c) => c == 'existing' ? 'Elegir una parada existente' : 'Crear una parada nueva');
    if (choice == null || !mounted) return;
    Stop? stop;
    if (choice == 'new') {
      stop = await editStop(context, null);
    } else {
      final stops = (await context.api.getAll('/stops', query: {'sort': 'landmark', ...context.entityFilter})).map(Stop.from).where((s) => !_links.any((l) => l.stopId == s.id)).toList();
      if (!mounted) return;
      stop = await pickFrom<Stop>(context, 'Parada', stops, (s) => s.landmark, subtitle: (s) => s.address);
    }
    if (stop == null || !mounted) return;
    await runAction(context, () => context.api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
          'itinerary': ResourceId('itineraries', _itinerary.id),
          'stop': ResourceId('stops', stop!.id),
        })));
    _load();
  }

  Future<void> _remove(ItineraryStop link) async {
    if (!await confirm(context, 'Quitar parada', '¿Quitar ${link.stop?.landmark ?? 'la parada'} de este itinerario?')) return;
    if (!mounted) return;
    await runAction(context, () => context.api.delete('/itinerary-stops/${link.id}'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_itinerary.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'Borrar itinerario', '¿Borrar ${_itinerary.name}?', destructive: true) || !context.mounted) return;
              if (await runAction(context, () => context.api.delete('/itineraries/${_itinerary.id}')) && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_location_alt), label: const Text('Parada')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              ListTile(title: const Text('Nombre'), subtitle: Text(_itinerary.name), trailing: const Icon(Icons.edit_outlined), onTap: () => _editField('name', 'Nombre', _itinerary.name)),
              ListTile(title: const Text('Descripción'), subtitle: Text(_itinerary.description ?? '—'), trailing: const Icon(Icons.edit_outlined), onTap: () => _editField('description', 'Descripción', _itinerary.description)),
              ListTile(title: const Text('Observación'), subtitle: Text(_itinerary.observation ?? '—'), trailing: const Icon(Icons.edit_outlined), onTap: () => _editField('observation', 'Observación', _itinerary.observation)),
              const SectionTitle('Paradas (arrastra para ordenar)'),
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  onReorderItem: _move,
                  children: [
                    for (var i = 0; i < _links.length; i++)
                      ListTile(
                        key: ValueKey(_links[i].id),
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(_links[i].stop?.landmark ?? ''),
                        subtitle: Text([
                          if (i == 0) 'Punto de salida',
                          if (i == _links.length - 1 && i > 0) 'Punto de regreso',
                          _links[i].stop?.address ?? '',
                        ].join(' · ')),
                        trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _remove(_links[i])),
                      ),
                  ],
                ),
              ),
            ]),
    );
  }
}
