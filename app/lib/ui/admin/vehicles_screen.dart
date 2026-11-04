import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/roles_api.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';

/// Vehículos y choferes de la Entidad elegida (Gestión; Jefe de Transporte y
/// Administrador). Crear, editar y eliminar (vehicles.manage); el chofer
/// habitual también con vehicles.assign_driver. Los choferes son quienes
/// tienen en la Entidad un rol que conduce (tracking.drive).
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<(List<Vehicle>, List<Worker>)>>();
  final _selection = SelectionController();
  List<Vehicle> _vehicles = const [];
  List<Worker> _drivers = const [];

  @override
  String get entityOperation => Op.vehiclesView;

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

  Future<(List<Vehicle>, List<Worker>)> _load() async {
    final api = context.api;
    final e = entity!;
    final vehicles = (await api.getAll('/vehicles', query: {'include': 'vehicleType', 'filter[entity]': e.id, 'sort': 'plate'})).map(Vehicle.from).toList();
    List<Worker> drivers = const [];
    try {
      drivers = await RolesApi(api).drivers(entityId: e.id);
    } catch (_) {}
    _vehicles = vehicles;
    _drivers = drivers;
    _selection.retain(vehicles.map((v) => v.id));
    return (vehicles, drivers);
  }

  Future<void> _open(Vehicle? vehicle) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => VehicleFormScreen(vehicle: vehicle, drivers: _drivers, entity: entity!)));
    if (saved == true) _view.currentState?.reload();
  }

  Future<void> _delete() async {
    final selected = _selection.selectedOf(_vehicles, (v) => v.id);
    final api = context.api;
    if (await runAction(context, () async {
      for (final v in selected) {
        await api.delete('/vehicles/${v.id}');
      }
    }, success: selected.length == 1 ? 'Vehículo eliminado.' : 'Vehículos eliminados.')) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = entity;
    final me = context.me;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selected = _selection.selectedOf(_vehicles, (v) => v.id);
        return AppScaffold(
          title: 'Vehículos y choferes',
          tab: MainTab.more,
          selection: _selection,
          actions: e == null
              ? const []
              : [
                  ActionItem(icon: Icons.add, label: 'Crear vehículo', enabled: me.can(Op.vehiclesManage, entityId: e.id), onPressed: () => _open(null)),
                  const ActionItem.divider(),
                  ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(selected.first)),
                  ActionItem(
                    icon: Icons.delete_outline,
                    label: 'Eliminar',
                    needs: ActionNeeds.some,
                    destructive: true,
                    enabled: me.can(Op.vehiclesManage, entityId: e.id),
                    confirmation: '¿Eliminar ${selected.length == 1 ? 'el vehículo ${formatPlate(selected.first.plate)}' : 'los vehículos seleccionados'}?',
                    onPressed: _delete,
                  ),
                ],
          body: entityPlaceholder() ??
              AsyncView<(List<Vehicle>, List<Worker>)>(
                key: _view,
                load: _load,
                builder: (context, data, reload) {
                  final (vehicles, drivers) = data;
                  final names = {for (final d in drivers) d.id: d.fullName};
                  return SelectableCardList<Vehicle>(
                    controller: _selection,
                    header: [entitySelector()],
                    sections: [CardSection(title: 'Vehículos', items: vehicles, hideIfEmpty: false, emptyText: 'No hay vehículos.')],
                    keyOf: (v) => v.id,
                    onOpen: _open,
                    cardBuilder: (context, v, selected, onTap, onLongPress) => InfoCard(
                      images: const [CardImage(icon: Icons.directions_bus)],
                      title: '${v.vehicleType?.name ?? ''} ${formatPlate(v.plate)}'.trim(),
                      lines: [capacityText(v.seats, v.standingCapacity), 'Chofer: ${names[v.driverId] ?? 'sin asignar'}'],
                      selected: selected,
                      onTap: onTap,
                      onLongPress: onLongPress,
                    ),
                  ).withFooter([
                    const SectionHeader('Choferes'),
                    if (drivers.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('No hay choferes.')),
                    for (final d in drivers)
                      InfoCard(
                        images: [CardImage(url: d.photoUrl, icon: Icons.person, round: true)],
                        title: d.fullName,
                        lines: [vehicles.where((v) => v.driverId == d.id).map((v) => formatPlate(v.plate)).join(', ').ifEmpty('Sin vehículo habitual')],
                      ),
                  ]);
                },
              ),
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

extension on SelectableCardList<Vehicle> {
  /// La lista con tarjetas fijas debajo (no seleccionables).
  Widget withFooter(List<Widget> footer) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
        SelectableCardList<Vehicle>(
          controller: controller,
          header: header,
          sections: sections,
          keyOf: keyOf,
          onOpen: onOpen,
          cardBuilder: cardBuilder,
          scrollable: false,
        ),
        ...footer,
      ]);
}

/// Crear o editar un vehículo. La capacidad total se calcula.
class VehicleFormScreen extends StatefulWidget {
  final Vehicle? vehicle;
  final List<Worker> drivers;
  final Entity entity;

  const VehicleFormScreen({super.key, this.vehicle, required this.drivers, required this.entity});

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.vehicle?.plate.replaceAll(' ', ''));
  late final _seats = TextEditingController(text: widget.vehicle?.seats.toString());
  late final _standing = TextEditingController(text: widget.vehicle?.standingCapacity.toString() ?? '0');
  late String? _typeId = widget.vehicle?.vehicleTypeId;
  late String? _driverId = widget.vehicle?.driverId;
  List<Named> _types = [];

  bool get _manage => context.me.can(Op.vehiclesManage, entityId: widget.entity.id);

  bool get _assignDriver => _manage || context.me.can(Op.vehiclesAssignDriver, entityId: widget.entity.id);

  @override
  void initState() {
    super.initState();
    context.api.getAll('/vehicle-types', query: {'sort': 'name'}).then((r) {
      if (mounted) setState(() => _types = r.map(Named.from).toList());
    }).catchError((_) {});
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final vehicle = widget.vehicle;
    final driver = _driverId == null ? null : ResourceId('workers', _driverId!);
    final body = _manage
        ? resourceData('vehicles', id: vehicle?.id, attributes: {
            'plate': _plate.text.replaceAll(' ', '').toUpperCase(),
            'seats': int.parse(_seats.text),
            'standingCapacity': int.parse(_standing.text),
          }, relationships: {
            'vehicleType': ResourceId('vehicle-types', _typeId!),
            'driver': driver,
            if (vehicle == null) 'entity': ResourceId('entities', widget.entity.id),
          })
        // Solo el chofer habitual (vehicles.assign_driver).
        : resourceData('vehicles', id: vehicle!.id, relationships: {'driver': driver});
    final api = context.api;
    final ok = await runAction(context, () => vehicle == null ? api.post('/vehicles', body) : api.patch('/vehicles/${vehicle.id}', body), success: 'Vehículo guardado.');
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final manage = _manage;
    final total = (int.tryParse(_seats.text) ?? 0) + (int.tryParse(_standing.text) ?? 0);
    return AppScaffold(
      title: vehicle == null ? 'Vehículo nuevo' : 'Vehículo ${formatPlate(vehicle.plate)}',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.save, label: 'Guardar', enabled: manage || (vehicle != null && _assignDriver), onPressed: _save),
        ActionItem(
          icon: Icons.delete_outline,
          label: 'Eliminar',
          destructive: true,
          enabled: vehicle != null && manage,
          confirmation: '¿Eliminar el vehículo ${formatPlate(vehicle?.plate)}?',
          onPressed: () async {
            if (await runAction(context, () => context.api.delete('/vehicles/${vehicle!.id}'), success: 'Vehículo eliminado.') && context.mounted) {
              Navigator.pop(context, true);
            }
          },
        ),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_types.length),
            initialValue: _types.any((t) => t.id == _typeId) ? _typeId : null,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
            items: [for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: manage ? (value) => setState(() => _typeId = value) : null,
            validator: (v) => manage && v == null ? 'Elija el tipo de vehículo.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _plate,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Matrícula', hintText: 'p. ej. B123456'),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(7),
              TextInputFormatter.withFunction((_, value) => value.copyWith(text: value.text.toUpperCase())),
            ],
            validator: (v) => RegExp(r'^[A-Z]\d{6}$').hasMatch((v ?? '').toUpperCase()) ? null : 'Escriba una letra y 6 dígitos, juntos (p. ej. B123456).',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _seats,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Capacidad sentados', hintText: 'p. ej. 45'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            validator: (v) => int.tryParse(v ?? '') == null ? 'Escriba la cantidad de asientos.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _standing,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Capacidad de pie', hintText: 'p. ej. 15'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            validator: (v) => int.tryParse(v ?? '') == null ? 'Escriba cuántos pueden ir de pie (0 si ninguno).' : null,
          ),
          const SizedBox(height: 12),
          ReadOnlyField(label: 'Capacidad total', value: '$total'),
          DropdownButtonFormField<String?>(
            initialValue: widget.drivers.any((d) => d.id == _driverId) ? _driverId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chofer habitual'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
              for (final d in widget.drivers) DropdownMenuItem<String?>(value: d.id, child: Text(d.fullName, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _assignDriver ? (value) => setState(() => _driverId = value) : null,
          ),
        ]),
      ),
    );
  }
}
