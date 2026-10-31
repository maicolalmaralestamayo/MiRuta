import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Crear o editar un viaje. Al crear, se puede copiar a un rango de fechas:
/// cada copia mantiene la hora de salida y la distancia hasta el regreso (7.10).
class TripFormScreen extends StatefulWidget {
  final Trip? trip;

  const TripFormScreen({super.key, this.trip});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  List<Itinerary> _itineraries = [];
  List<Vehicle> _vehicles = [];
  List<(String, String)> _drivers = [];
  String? _itineraryId;
  String? _vehicleId;
  String? _driverId;
  late DateTime _departs;
  late DateTime _returns;
  String _status = TripStatus.unconfirmed;
  DateTimeRange? _copyRange;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.trip != null;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _departs = trip?.departsAt ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17);
    _returns = trip?.returnsAt ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1, 6, 30);
    _itineraryId = trip?.itineraryId;
    _vehicleId = trip?.vehicleId;
    _driverId = trip?.driverId;
    _status = trip?.status ?? TripStatus.unconfirmed;
    _load();
  }

  Future<void> _load() async {
    final api = context.api;
    try {
      final me = context.me;
      // El Administrador planifica en la Entidad elegida en Gestión; los
      // demás solo ven la suya.
      final entityFilter = context.entityFilter;
      final entityId = context.session.adminEntity?.id;
      final itineraries = (await api.getAll('/itineraries', query: {'sort': 'name', ...entityFilter})).map(Itinerary.from).where((i) => me.canPlan(i.id)).toList();
      final vehicles = (await api.getAll('/vehicles', query: {'include': 'vehicleType', ...entityFilter})).map(Vehicle.from).toList();
      final drivers = (await api.getAll('/drivers', query: {'include': 'worker'}))
          .where((r) => entityId == null || r.related('worker')?.relId('entity')?.id == entityId)
          .map((r) => (r.id, PersonName.from(r.related('worker')).full))
          .toList();
      setState(() {
        _itineraries = itineraries;
        if (_itineraryId == null && itineraries.length == 1) _itineraryId = itineraries.first.id;
        _vehicles = vehicles;
        _drivers = drivers;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Map<String, dynamic> _data(DateTime departs, DateTime returns) => resourceData('trips', id: widget.trip?.id, attributes: {
        'departsAt': departs.toUtc().toIso8601String(),
        'returnsAt': returns.toUtc().toIso8601String(),
        'status': _status,
      }, relationships: {
        'itinerary': ResourceId('itineraries', _itineraryId!),
        'vehicle': ResourceId('vehicles', _vehicleId!),
        'driver': ResourceId('drivers', _driverId!),
      })['data'] as Map<String, dynamic>;

  Future<void> _save() async {
    if (_itineraryId == null || _vehicleId == null || _driverId == null) {
      setState(() => _error = 'Elige itinerario, vehículo y chofer.');
      return;
    }
    if (!_returns.isAfter(_departs)) {
      setState(() => _error = 'El regreso debe ser posterior a la salida.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.api;
      if (_editing) {
        await api.patch('/trips/${widget.trip!.id}', {'data': _data(_departs, _returns)});
      } else if (_copyRange == null) {
        await api.post('/trips', {'data': _data(_departs, _returns)});
      } else {
        // Una copia por día del rango, todas o ninguna.
        final duration = _returns.difference(_departs);
        final operations = <Map<String, dynamic>>[];
        for (var day = _copyRange!.start; !day.isAfter(_copyRange!.end); day = DateTime(day.year, day.month, day.day + 1)) {
          final departs = DateTime(day.year, day.month, day.day, _departs.hour, _departs.minute);
          operations.add({'op': 'add', 'data': _data(departs, departs.add(duration))});
        }
        await api.atomicOperations(operations);
      }
      if (mounted) {
        showMessage(context, _editing ? 'Viaje guardado' : 'Viaje(s) creado(s)');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      final overlaps = error.errors.where((e) => e.code == 'TRIP_OVERLAP').toList();
      setState(() => _error = overlaps.length > 1
          ? 'Se solapan ${overlaps.length} días:\n${overlaps.map((e) => '• ${e.meta['departsAt'] == null ? e.message : formatDate(DateTime.parse('${e.meta['departsAt']}').toLocal())}').join('\n')}\nNo se creó ninguno.'
          : error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicles.where((v) => v.id == _vehicleId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar viaje' : 'Nuevo viaje')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _itineraryId,
          decoration: const InputDecoration(labelText: 'Itinerario'),
          items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
          onChanged: (value) => setState(() => _itineraryId = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _vehicleId,
          decoration: const InputDecoration(labelText: 'Vehículo'),
          items: [for (final v in _vehicles) DropdownMenuItem(value: v.id, child: Text('${v.vehicleType?.name ?? ''} ${v.plate} (${v.totalCapacity} plazas)'))],
          onChanged: (value) => setState(() {
            _vehicleId = value;
            // Se propone el chofer habitual del vehículo.
            final habitual = _vehicles.firstWhere((v) => v.id == value).driverId;
            if (habitual != null) _driverId = habitual;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _drivers.any((d) => d.$1 == _driverId) ? _driverId : null,
          decoration: InputDecoration(labelText: 'Chofer', helperText: vehicle?.driverId == _driverId && _driverId != null ? 'Chofer habitual del vehículo' : null),
          items: [for (final d in _drivers) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
          onChanged: (value) => setState(() => _driverId = value),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.north_east),
          title: Text('Salida: ${formatDateTime(_departs)}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final value = await _pickDateTime(_departs);
            if (value != null) setState(() => _departs = value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.south_west),
          title: Text('Regreso: ${formatDateTime(_returns)}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final value = await _pickDateTime(_returns);
            if (value != null) setState(() => _returns = value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: [
            for (final status in [TripStatus.unconfirmed, TripStatus.confirmed, if (_editing) TripStatus.completed, if (_editing) TripStatus.cancelled])
              DropdownMenuItem(value: status, child: Text(TripStatus.label(status))),
          ],
          onChanged: (value) => setState(() => _status = value!),
        ),
        if (!_editing) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Copiar a un rango de fechas'),
            subtitle: Text(_copyRange == null ? 'Un viaje por cada día del rango' : 'Del ${formatDate(_copyRange!.start)} al ${formatDate(_copyRange!.end)} (${_copyRange!.duration.inDays + 1} viajes)'),
            value: _copyRange != null,
            onChanged: (value) async {
              if (!value) return setState(() => _copyRange = null);
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 366)),
                initialDateRange: DateTimeRange(start: _departs, end: _departs.add(const Duration(days: 4))),
              );
              if (range != null) setState(() => _copyRange = range);
            },
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_editing ? 'Guardar' : 'Crear')),
      ]),
    );
  }
}
