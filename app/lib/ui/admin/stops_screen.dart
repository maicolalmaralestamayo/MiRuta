import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'management.dart';
import 'map_picker.dart';

/// Las paradas se gestionan desde la ficha del itinerario (docs/09 §32):
/// aquí solo queda su formulario.

/// Dirección de la parada: "Calle 1 entre A y B".
String stopAddress(Stop stop) {
  final between = [stop.crossStreet1, stop.crossStreet2].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
  return '${stop.street}${between.isEmpty ? '' : ' entre ${between.join(' y ')}'}';
}

/// Crear o editar una parada. Devuelve la parada guardada (o la borrada).
/// [itineraryCount] es en cuántos itinerarios se usa: al editarla se avisa de
/// que el cambio afecta a todos ellos.
/// [entityId] es la Entidad de la parada (obligatoria al crearla).
Future<Stop?> editStop(BuildContext context, Stop? stop, {int itineraryCount = 0, String? entityId}) =>
    Navigator.push<Stop>(context, MaterialPageRoute(builder: (_) => _StopForm(stop: stop, itineraryCount: itineraryCount, entityId: entityId)));

class _StopForm extends StatefulWidget {
  final Stop? stop;
  final int itineraryCount;
  final String? entityId;

  const _StopForm({this.stop, this.itineraryCount = 0, this.entityId});

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
  bool _pointMissing = false;

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    setState(() => _pointMissing = _point == null);
    if (!valid || _point == null) return;
    if (widget.stop != null &&
        widget.itineraryCount > 1 &&
        !await confirm(context, 'Guardar parada', 'El cambio afecta a los ${widget.itineraryCount} itinerarios que usan esta parada. ¿Guardarlo?', accept: 'Guardar parada')) {
      return;
    }
    if (!mounted) return;
    final entityId = widget.entityId;
    final body = resourceData('stops', id: widget.stop?.id, relationships: widget.stop == null && entityId != null ? {'entity': ResourceId('entities', entityId)} : null, attributes: {
      'landmark': _landmark.text.trim(),
      'street': _street.text.trim(),
      'crossStreet1': _optional(_cross1),
      'crossStreet2': _optional(_cross2),
      'latitude': _point!.latitude,
      'longitude': _point!.longitude,
    });
    final api = context.api;
    final document = widget.stop == null ? await api.post('/stops', body) : await api.patch('/stops/${widget.stop!.id}', body);
    if (mounted) Navigator.pop(context, Stop.from(document.resource));
  }

  late Stop? _current = widget.stop;

  Future<void> _reloadImage() async {
    final id = _current?.id;
    if (id == null) return;
    try {
      final stop = Stop.from((await context.api.get('/stops/$id')).resource);
      if (mounted) setState(() => _current = stop);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    final manage = widget.entityId == null ? context.me.canAnywhere(Op.stopsManage) : context.me.can(Op.stopsManage, entityId: widget.entityId);
    return AppScaffold(
      title: stop == null ? 'Parada nueva' : 'Parada',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.save, label: stop == null ? 'Crear parada' : 'Guardar parada', enabled: manage, onPressed: _save),
        ActionItem(
          icon: Icons.delete_outline,
          label: 'Eliminar',
          destructive: true,
          enabled: stop != null && manage,
          confirmation: stop == null
              ? null
              : '¿Eliminar la parada ${stop.landmark}${widget.itineraryCount > 0 ? '? Se quitará de ${plural(widget.itineraryCount, 'itinerario', 'itinerarios')}' : ''}?',
          onPressed: () async {
            if (await runAction(context, () => context.api.delete('/stops/${stop!.id}')) && context.mounted) Navigator.pop(context, stop);
          },
        ),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          ImageEditor(url: _current?.imageUrl, icon: Icons.place, uploadPath: stop != null && manage ? '/stops/${stop.id}/image' : null, onChanged: _reloadImage),
          if (stop == null) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: Text('La imagen se pone después de crearla.'))),
          const SizedBox(height: 12),
          if (stop != null && widget.itineraryCount > 1)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Los cambios afectan a los ${widget.itineraryCount} itinerarios que usan esta parada.'),
              ),
            ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _landmark,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Punto de referencia', hintText: 'p. ej. Parque central'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v!.trim().isEmpty ? 'Escriba el punto de referencia.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _street,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Calle', hintText: 'p. ej. Calle 1'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v!.trim().isEmpty ? 'Escriba la calle.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cross1,
            decoration: const InputDecoration(labelText: 'Entre la calle (opcional)', hintText: 'p. ej. Calle A'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cross2,
            decoration: const InputDecoration(labelText: 'Y la calle (opcional)', hintText: 'p. ej. Calle B'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final point = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _point)));
              if (point != null) {
                setState(() {
                  _point = point;
                  _pointMissing = false;
                });
              }
            },
            child: InputDecorator(
              isEmpty: _point == null,
              decoration: InputDecoration(
                labelText: 'Ubicación en el mapa',
                errorText: _pointMissing ? 'Marque la parada en el mapa.' : null,
                suffixIcon: const Icon(Icons.map_outlined),
              ),
              child: _point == null ? null : Text('${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}'),
            ),
          ),
        ]),
      ),
    );
  }
}
