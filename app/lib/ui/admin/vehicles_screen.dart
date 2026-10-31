import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Vehículos con su chofer habitual. La capacidad total se calcula.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final _view = GlobalKey<AsyncViewState<(List<Vehicle>, Map<String, String>)>>();

  Future<(List<Vehicle>, Map<String, String>)> _load() async {
    final api = context.api;
    final vehicles = (await api.getAll('/vehicles', query: {'include': 'vehicleType', ...context.entityFilter})).map(Vehicle.from).toList();
    final entityId = context.session.adminEntity?.id;
    final drivers = {
      for (final r in await api.getAll('/drivers', query: {'include': 'worker'}))
        if (entityId == null || r.related('worker')?.relId('entity')?.id == entityId) r.id: PersonName.from(r.related('worker')).full,
    };
    return (vehicles, drivers);
  }

  Future<void> _edit(Vehicle? vehicle, Map<String, String> drivers) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _VehicleForm(vehicle: vehicle, drivers: drivers)));
    if (saved == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<(List<Vehicle>, Map<String, String>)>(
      key: _view,
      load: _load,
      builder: (context, data, reload) {
        final (vehicles, drivers) = data;
        return Scaffold(
          appBar: AppBar(title: const Text('Vehículos y choferes')),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null, drivers), icon: const Icon(Icons.add), label: const Text('Vehículo')),
          body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
            for (final v in vehicles)
              ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text('${v.vehicleType?.name ?? ''} ${v.plate}'),
                subtitle: Text('${v.seats} asientos + ${v.standingCapacity} de pie = ${v.totalCapacity} · Chofer: ${drivers[v.driverId] ?? 'sin asignar'}'),
                onTap: () => _edit(v, drivers),
              ),
            const SectionTitle('Choferes'),
            for (final entry in drivers.entries)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(entry.value),
                subtitle: Text(vehicles.where((v) => v.driverId == entry.key).map((v) => v.plate).join(', ').ifEmpty('Sin vehículo asignado')),
              ),
            if (drivers.isEmpty) const ListTile(title: Text('No hay choferes. Los trabajadores lo solicitan en Solicitudes.')),
          ]),
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _VehicleForm extends StatefulWidget {
  final Vehicle? vehicle;
  final Map<String, String> drivers;

  const _VehicleForm({this.vehicle, required this.drivers});

  @override
  State<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<_VehicleForm> {
  final _form = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.vehicle?.plate);
  late final _seats = TextEditingController(text: widget.vehicle?.seats.toString());
  late final _standing = TextEditingController(text: widget.vehicle?.standingCapacity.toString() ?? '0');
  late String? _typeId = widget.vehicle?.vehicleTypeId;
  late String? _driverId = widget.vehicle?.driverId;
  List<Named> _types = [];

  @override
  void initState() {
    super.initState();
    context.api.getAll('/vehicle-types').then((r) {
      if (mounted) setState(() => _types = r.map(Named.from).toList());
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final entity = widget.vehicle == null ? context.entityRelationship() : const <String, ResourceId?>{};
    if (entity == null) return;
    final body = resourceData('vehicles', id: widget.vehicle?.id, attributes: {
      'plate': _plate.text.trim(),
      'seats': int.parse(_seats.text),
      'standingCapacity': int.parse(_standing.text),
    }, relationships: {
      'vehicleType': ResourceId('vehicle-types', _typeId!),
      'driver': _driverId == null ? null : ResourceId('drivers', _driverId!),
      ...entity,
    });
    final ok = await runAction(context, () => widget.vehicle == null ? context.api.post('/vehicles', body) : context.api.patch('/vehicles/${widget.vehicle!.id}', body));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final total = (int.tryParse(_seats.text) ?? 0) + (int.tryParse(_standing.text) ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle == null ? 'Nuevo vehículo' : 'Vehículo'),
        actions: [
          if (widget.vehicle != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, 'Borrar vehículo', '¿Borrar ${widget.vehicle!.plate}?', destructive: true) || !context.mounted) return;
                if (await runAction(context, () => context.api.delete('/vehicles/${widget.vehicle!.id}')) && context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(
            initialValue: _typeId,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (value) => setState(() => _typeId = value),
            validator: (v) => v == null ? 'Elige el tipo' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _plate, decoration: const InputDecoration(labelText: 'Matrícula'), textCapitalization: TextCapitalization.characters, validator: (v) => v!.trim().isEmpty ? 'Obligatoria' : null),
          const SizedBox(height: 12),
          TextFormField(
            controller: _seats,
            decoration: const InputDecoration(labelText: 'Asientos (sin el del chofer)'),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (v) => int.tryParse(v ?? '') == null ? 'Número' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _standing,
            decoration: const InputDecoration(labelText: 'Capacidad de pie'),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (v) => int.tryParse(v ?? '') == null ? 'Número' : null,
          ),
          Padding(padding: const EdgeInsets.all(8), child: Text('Capacidad total: $total pasajeros')),
          DropdownButtonFormField<String?>(
            initialValue: _driverId,
            decoration: const InputDecoration(labelText: 'Chofer habitual'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
              for (final d in widget.drivers.entries) DropdownMenuItem<String?>(value: d.key, child: Text(d.value)),
            ],
            onChanged: (value) => setState(() => _driverId = value),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ]),
      ),
    );
  }
}
