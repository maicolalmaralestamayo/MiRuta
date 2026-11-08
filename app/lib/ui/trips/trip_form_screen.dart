import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import 'trip_line_screen.dart';
import 'trip_workers_screen.dart';

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseTime(String text) {
  final parts = text.split(':');
  if (parts.length < 2) return null;
  return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
}

Future<List<NomenclatorItem>> _vehicleTypes(BuildContext context) async =>
    (await context.read<Session>().api.getAll('/vehicle-types', query: {'filter[active]': 'true'})).map(NomenclatorItem.from).toList();

/// Formulario del viaje (maqueta G18 n.º 9). Solo se edita mientras está
/// Planificado (docs/11 §11.47); el sentido y el itinerario no cambian.
class TripFormScreen extends StatefulWidget {
  final String tripId;

  const TripFormScreen({super.key, required this.tripId});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  final _view = GlobalKey<DataViewState<(Trip, List<NomenclatorItem>)>>();
  DateTime? _date;
  TimeOfDay? _time;
  String? _vehicleType;
  final _observation = TextEditingController();
  String? _loadedId;

  Future<(Trip, List<NomenclatorItem>)> _load() async {
    final api = context.read<Session>().api;
    final typesFuture = _vehicleTypes(context);
    final trip = Trip.from((await api.get('/trips/${widget.tripId}', query: {'include': 'itinerary,vehicleType'})).resource);
    final types = await typesFuture;
    if (_loadedId != trip.updatedKey) {
      _loadedId = trip.updatedKey;
      _date = trip.date;
      _time = _parseTime(trip.departureTime);
      _vehicleType = trip.vehicleTypeId;
      _observation.text = trip.observation ?? '';
    }
    return (trip, types);
  }

  bool _canManage(Trip t) {
    final me = context.read<Session>().me!;
    return me.isAdmin || me.isChiefOf(t.itineraryId);
  }

  Future<void> _save(Trip t) async {
    await context.read<Session>().api.patch('/trips/${t.id}', resourceData('trips', id: t.id, attributes: {
      'date': apiDay(_date!),
      'departureTime': _hhmm(_time!),
      'observation': _observation.text.trim().isEmpty ? null : _observation.text.trim(),
    }, relationships: {'vehicleType': ResourceId('vehicle-types', _vehicleType!)}));
    if (mounted) showMessage(context, 'Viaje guardado.');
    _view.currentState?.reload();
  }

  Future<void> _status(Trip t, String status, String verb) async {
    if (!await confirm(context, verb, '¿$verb el ${t.title.toLowerCase()}?', accept: verb, icon: Icons.check, destructive: status == TripStatus.cancelled)) return;
    if (!mounted) return;
    await context.read<Session>().api.patch('/trips/${t.id}', resourceData('trips', id: t.id, attributes: {'status': status}));
    _view.currentState?.reload();
  }

  Future<void> _detentionCause(Trip t) async {
    final api = context.read<Session>().api;
    final causes = (await api.getAll('/detention-causes', query: {'filter[active]': 'true'})).map(NomenclatorItem.from).toList();
    if (!mounted) return;
    const none = NomenclatorItem(id: '', kind: 'detention-causes', name: 'Sin causa');
    final cause = await pickOne<NomenclatorItem>(context, 'Causa de la detención', [none, ...causes], (c) => c.name);
    if (cause == null) return;
    await api.patch('/trips/${t.id}', resourceData('trips', id: t.id, relationships: {'detentionCause': cause.id.isEmpty ? null : ResourceId('detention-causes', cause.id)}));
    if (mounted) showMessage(context, 'Causa indicada.');
  }

  List<ActionItem> _actions() {
    final data = _view.currentState?.data;
    if (data == null) return const [];
    final t = data.$1;
    final me = context.read<Session>().me!;
    final manage = _canManage(t);
    return [
      if (manage && t.isPlanned) ActionItem(Icons.save_outlined, 'Guardar', () => _save(t)),
      ActionItem(Icons.timeline, 'Ver recorrido', () => push(context, TripLineScreen(tripId: t.id))),
      ActionItem(Icons.groups_outlined, 'Trabajadores', () => push(context, TripWorkersScreen(trip: t))),
      if (manage && t.isPlanned) ActionItem(Icons.play_arrow, 'Empezar viaje', () => _status(t, TripStatus.running, 'Empezar')),
      if (manage && t.isRunning) ActionItem(Icons.flag_outlined, 'Terminar viaje', () => _status(t, TripStatus.finished, 'Terminar')),
      if (manage && t.isRunning && t.vehicleState == 'detenido') ActionItem(Icons.report_outlined, 'Causa de detención', () => _detentionCause(t)),
      if (manage && t.isPlanned && (me.isAdmin || t.createdById == me.userId))
        ActionItem(Icons.cancel_outlined, 'Cancelar viaje', () => _status(t, TripStatus.cancelled, 'Cancelar'), destructive: true),
      if (manage && !t.isRunning)
        ActionItem(Icons.delete_outline, 'Eliminar', () async {
          if (!await confirmDelete(context, 'el ${t.title.toLowerCase()}')) return;
          if (!mounted) return;
          await context.read<Session>().api.delete('/trips/${t.id}');
          if (mounted) Navigator.pop(context, true);
        }, destructive: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Viaje',
      tab: MainTab.trips,
      actions: _actions,
      body: DataView<(Trip, List<NomenclatorItem>)>(
        key: _view,
        kinds: const {'trips'},
        load: _load,
        builder: (context, data, reload) {
          final t = data.$1;
          final types = data.$2;
          final edit = _canManage(t) && t.isPlanned;
          final type = types.where((v) => v.id == _vehicleType).firstOrNull;
          return ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
            FormText(label: 'Itinerario', value: t.itineraryName ?? '', readOnly: true),
            FormText(label: 'Sentido', value: t.directionName, readOnly: true),
            FormText(
              key: ValueKey('d$_date'),
              label: 'Fecha',
              value: formatDate(_date),
              icon: Icons.event,
              enabled: edit,
              onTap: edit
                  ? () async {
                      final d = await showDatePicker(context: context, initialDate: _date ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
                      if (d != null) setState(() => _date = d);
                    }
                  : null,
            ),
            FormText(
              key: ValueKey('t$_time'),
              label: 'Hora de salida',
              value: _time == null ? '' : _hhmm(_time!),
              icon: Icons.schedule,
              enabled: edit,
              onTap: edit
                  ? () async {
                      final v = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 7, minute: 0), builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
                      if (v != null) setState(() => _time = v);
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: edit
                  ? DropdownButtonFormField<String>(
                      initialValue: types.any((v) => v.id == _vehicleType) ? _vehicleType : null,
                      decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
                      items: [for (final v in types) DropdownMenuItem(value: v.id, child: Text(v.vehicleLabel))],
                      onChanged: (v) => setState(() => _vehicleType = v),
                    )
                  : TextFormField(
                      initialValue: type?.vehicleLabel ?? t.vehicleTypeName ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Tipo de vehículo', suffixIcon: Icon(Icons.lock_outline, size: 18)),
                    ),
            ),
            FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 2),
            FormText(label: 'Estado', value: TripStatus.name(t.status), readOnly: true),
            FormText(label: 'Ocupación prevista', value: t.occupancy, readOnly: true),
            if (t.myState != null) FormText(label: 'Mi estado', value: WorkerState.name(t.myState), readOnly: true),
          ]);
        },
      ),
    );
  }
}

extension on Trip {
  String get updatedKey => '$id|$date|$departureTime|$vehicleTypeId|$observation';
}

/// Planificar un viaje a mano (docs/11 §11.33): casillas Ida y Regreso, cada
/// una con su hora y su tipo de vehículo; se crean dos viajes independientes.
class PlanTripScreen extends StatefulWidget {
  final String? itineraryId;

  const PlanTripScreen({super.key, this.itineraryId});

  @override
  State<PlanTripScreen> createState() => _PlanTripScreenState();
}

class _PlanTripScreenState extends State<PlanTripScreen> {
  Itinerary? _itinerary;
  List<Itinerary> _itineraries = const [];
  List<NomenclatorItem> _types = const [];
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _outbound = true;
  bool _return = true;
  TimeOfDay _outboundTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _returnTime = const TimeOfDay(hour: 17, minute: 30);
  String? _outboundType;
  String? _returnType;
  final _observation = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = context.read<Session>().api;
    final me = context.read<Session>().me!;
    try {
      var list = (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[active]': 'true'})).map(Itinerary.from).toList();
      if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
      final types = mounted ? await _vehicleTypes(context) : <NomenclatorItem>[];
      if (!mounted) return;
      setState(() {
        _itineraries = list;
        _types = types;
        _itinerary = list.where((i) => i.id == widget.itineraryId).firstOrNull ?? (list.length == 1 ? list.first : null);
        _outboundType = types.firstOrNull?.id;
        _returnType = types.firstOrNull?.id;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _plan() async {
    final itinerary = _itinerary;
    if (itinerary == null) throw StateError('Elija el itinerario.');
    if (!_outbound && !_return) throw StateError('Marque Ida, Regreso o los dos.');
    final api = context.read<Session>().api;
    final created = <String>[];
    for (final (direction, enabled, time, type) in [('ida', _outbound, _outboundTime, _outboundType), ('regreso', _return, _returnTime, _returnType)]) {
      if (!enabled) continue;
      if (type == null) throw StateError('Elija el tipo de vehículo.');
      await api.post('/trips', resourceData('trips', attributes: {
        'direction': direction,
        'date': apiDay(_date),
        'departureTime': _hhmm(time),
        if (_observation.text.trim().isNotEmpty) 'observation': _observation.text.trim(),
      }, relationships: {
        'itinerary': ResourceId('itineraries', itinerary.id),
        'vehicleType': ResourceId('vehicle-types', type),
      }));
      created.add(direction);
    }
    if (!mounted) return;
    showMessage(context, created.length == 2 ? 'Viajes de ida y regreso planificados.' : 'Viaje de ${created.first} planificado.');
    Navigator.pop(context, true);
  }

  Widget _leg(String label, bool value, ValueChanged<bool> onChanged, TimeOfDay time, ValueChanged<TimeOfDay> onTime, String? type, ValueChanged<String?> onType) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(children: [
        CheckboxListTile(value: value, onChanged: (v) => onChanged(v ?? false), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), controlAffinity: ListTileControlAffinity.leading),
        if (value) ...[
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Hora de salida'),
            subtitle: Text(_hhmm(time)),
            onTap: () async {
              final v = await showTimePicker(context: context, initialTime: time, builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
              if (v != null) onTime(v);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
              items: [for (final v in _types) DropdownMenuItem(value: v.id, child: Text(v.vehicleLabel))],
              onChanged: onType,
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold.list(
      title: 'Planificar viaje',
      tab: MainTab.trips,
      actions: () => [ActionItem(Icons.event_available, 'Planificar', _plan)],
      children: [
        SelectorCard(
          icon: Icons.route,
          title: _itinerary?.name ?? 'Elija el itinerario',
          lines: ['Itinerario', if (_itinerary?.entityAbbreviation != null) _itinerary!.entityAbbreviation!],
          enabled: _itineraries.length > 1,
          onTap: () async {
            final i = await pickOne<Itinerary>(context, 'Itinerario', _itineraries, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? '');
            if (i != null) setState(() => _itinerary = i);
          },
        ),
        FormText(
          key: ValueKey(_date),
          label: 'Fecha',
          value: formatDate(_date),
          icon: Icons.event,
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime(2100));
            if (d != null) setState(() => _date = d);
          },
        ),
        _leg('Ida', _outbound, (v) => setState(() => _outbound = v), _outboundTime, (v) => setState(() => _outboundTime = v), _outboundType, (v) => setState(() => _outboundType = v)),
        _leg('Regreso', _return, (v) => setState(() => _return = v), _returnTime, (v) => setState(() => _returnTime = v), _returnType, (v) => setState(() => _returnType = v)),
        FormText(controller: _observation, label: 'Observación', maxLines: 2),
      ],
    );
  }
}
