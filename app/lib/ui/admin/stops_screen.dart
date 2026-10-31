import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import 'map_picker.dart';

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key});

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Stop>>>();
  String _search = '';

  Future<List<Stop>> _load() async =>
      (await context.api.getAll('/stops', query: {...context.entityFilter, if (_search.isNotEmpty) 'filter[search]': _search})).map(Stop.from).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paradas')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Parada'),
        onPressed: () async {
          if (await editStop(context, null) != null) _view.currentState?.reload();
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por punto o calle', isDense: true),
            onSubmitted: (value) {
              _search = value.trim();
              _view.currentState?.reload();
            },
          ),
        ),
        Expanded(
          child: AsyncView<List<Stop>>(
            key: _view,
            load: _load,
            builder: (context, stops, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              for (final stop in stops)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(stop.landmark),
                  subtitle: Text(stop.address),
                  onTap: () async {
                    if (await editStop(context, stop) != null) reload();
                  },
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Crear o editar una parada. Devuelve la parada guardada.
Future<Stop?> editStop(BuildContext context, Stop? stop) => Navigator.push<Stop>(context, MaterialPageRoute(builder: (_) => _StopForm(stop: stop)));

class _StopForm extends StatefulWidget {
  final Stop? stop;

  const _StopForm({this.stop});

  @override
  State<_StopForm> createState() => _StopFormState();
}

class _StopFormState extends State<_StopForm> {
  final _form = GlobalKey<FormState>();
  late final _landmark = TextEditingController(text: widget.stop?.landmark);
  late final _street = TextEditingController(text: widget.stop?.street);
  late final _cross1 = TextEditingController(text: widget.stop?.crossStreet1);
  late final _cross2 = TextEditingController(text: widget.stop?.crossStreet2);
  late LatLng? _point = widget.stop == null ? null : LatLng(widget.stop!.latitude, widget.stop!.longitude);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null) {
      showMessage(context, 'Marca la parada en el mapa.');
      return;
    }
    final entity = widget.stop == null ? context.entityRelationship() : const <String, ResourceId?>{};
    if (entity == null) return;
    final body = resourceData('stops', id: widget.stop?.id, relationships: entity.isEmpty ? null : entity, attributes: {
      'landmark': _landmark.text.trim(),
      'street': _street.text.trim(),
      'crossStreet1': _cross1.text.trim().isEmpty ? null : _cross1.text.trim(),
      'crossStreet2': _cross2.text.trim().isEmpty ? null : _cross2.text.trim(),
      'latitude': _point!.latitude,
      'longitude': _point!.longitude,
    });
    try {
      final api = context.api;
      final document = widget.stop == null ? await api.post('/stops', body) : await api.patch('/stops/${widget.stop!.id}', body);
      if (mounted) Navigator.pop(context, Stop.from(document.resource));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stop == null ? 'Nueva parada' : 'Parada'),
        actions: [
          if (widget.stop != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, 'Borrar parada', '¿Borrar ${widget.stop!.landmark}?', destructive: true) || !context.mounted) return;
                if (await runAction(context, () => context.api.delete('/stops/${widget.stop!.id}')) && context.mounted) Navigator.pop(context, widget.stop);
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _landmark, decoration: const InputDecoration(labelText: 'Punto de referencia'), validator: (v) => v!.trim().isEmpty ? 'Obligatorio' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _street, decoration: const InputDecoration(labelText: 'Calle'), validator: (v) => v!.trim().isEmpty ? 'Obligatoria' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _cross1, decoration: const InputDecoration(labelText: 'Entrecalle 1')),
          const SizedBox(height: 12),
          TextFormField(controller: _cross2, decoration: const InputDecoration(labelText: 'Entrecalle 2')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: Text(_point == null ? 'Marcar en el mapa' : '${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}'),
            onPressed: () async {
              final point = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _point)));
              if (point != null) setState(() => _point = point);
            },
          ),
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, child: const Text('Guardar')),
        ]),
      ),
    );
  }
}
