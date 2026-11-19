import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/busy_scope.dart';
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
import 'trip_card.dart';
import 'trip_line_screen.dart';
import 'trip_workers_screen.dart';

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Selector de hora de 12 h con a. m. / p. m., en un diálogo que se abre al
/// tocar la Hora de salida (docs/11 §11.65, puntos 15 y 21).
/// Selector de hora (docs/11 §11.67): solo un reloj digital de 24 h con dos
/// campos, hora (00–23) y minutos (00–59); sin reloj analógico ni a. m./p. m.
Future<TimeOfDay?> pickTime24(BuildContext context, TimeOfDay initial) => showDialog<TimeOfDay>(
      context: context,
      builder: (context) => _TimeDialog(initial: initial),
    );

class _TimeDialog extends StatefulWidget {
  final TimeOfDay initial;

  const _TimeDialog({required this.initial});

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  final _form = GlobalKey<FormState>();
  late final _hour = TextEditingController(text: widget.initial.hour.toString().padLeft(2, '0'));
  late final _minute = TextEditingController(text: widget.initial.minute.toString().padLeft(2, '0'));

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  static String? _check(String? v, int max, String what) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 0 || n > max ? '00–${max.toString().padLeft(2, '0')}' : null;
  }

  void _accept() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, TimeOfDay(hour: int.parse(_hour.text.trim()), minute: int.parse(_minute.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displaySmall;
    Widget field(TextEditingController c, String label, int max, {bool last = false}) => SizedBox(
          width: 96,
          child: TextFormField(
            controller: c,
            autofocus: !last,
            textAlign: TextAlign.center,
            style: style,
            keyboardType: TextInputType.number,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
            validator: (v) => _check(v, max, label),
            onTap: () => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length),
            onFieldSubmitted: last ? (_) => _accept() : null,
          ),
        );
    return AppDialog(
      icon: const Icon(Icons.schedule, size: 32),
      title: 'Hora de salida',
      content: Form(
        key: _form,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          field(_hour, 'Hora', 23),
          Padding(padding: const EdgeInsets.fromLTRB(8, 12, 8, 0), child: Text(':', style: style)),
          field(_minute, 'Minutos', 59, last: true),
        ]),
      ),
      buttons: [
        primaryButton(context, 'Confirmar', Icons.check, _accept),
        cancelButton(context),
      ],
    );
  }
}

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

  /// Valores cargados, para «Salir sin guardar».
  List<Object?>? _initial;
  bool _editable = false;

  List<Object?> _snapshot() => [_date, _time, _vehicleType, _observation.text];

  bool get _dirty => _editable && _initial != null && !listEquals(_initial, _snapshot());

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
      _initial = _snapshot();
    }
    _editable = mounted && _canManage(trip) && trip.isPlanned;
    return (trip, types);
  }

  bool _canManage(Trip t) {
    final me = context.read<Session>().me!;
    return me.isAdmin || me.isChiefOf(t.itineraryId);
  }

  Future<bool> _save(Trip t) async {
    final ok = await runAction(context, label: 'Actualizando Viaje', () async {
      await context.read<Session>().api.patch('/trips/${t.id}', resourceData('trips', id: t.id, attributes: {
        'date': apiDay(_date!),
        'departureTime': _hhmm(_time!),
        'observation': _observation.text.trim().isEmpty ? null : _observation.text.trim(),
      }, relationships: {'vehicleType': ResourceId('vehicle-types', _vehicleType!)}));
    });
    if (!ok) return false;
    _initial = _snapshot();
    _view.currentState?.reload();
    return true;
  }

  Future<void> _status(Trip t, String status) async {
    final cancelling = status == TripStatus.cancelled;
    final (verb, doing) = tripStatusVerb(status);
    if (!await confirm(context, '$verb Viaje', '¿$verb el ${t.title.toLowerCase()}?',
        accept: '$verb Viaje', icon: cancelling ? Icons.cancel_outlined : Icons.check, destructive: cancelling, headerIcon: cancelling ? Icons.cancel_outlined : Icons.directions_bus_outlined)) {
      return;
    }
    if (!mounted) return;
    BusyScope.relabel('$doing Viaje');
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
  }

  List<ActionItem> _actions() {
    final data = _view.currentState?.data;
    if (data == null) return const [];
    final t = data.$1;
    final me = context.read<Session>().me!;
    final manage = _canManage(t);
    return [
      if (manage && t.isPlanned) ActionItem(Icons.save_outlined, 'Guardar', () => _save(t)),
      if (manage) ActionItem(Icons.event_available, 'Crear Viaje', () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PlanTripScreen(itineraryId: t.itineraryId)), result: true)),
      ActionItem(Icons.timeline, 'Ver recorrido', () => push(context, TripLineScreen(tripId: t.id))),
      ActionItem(Icons.groups_outlined, 'Consultar Trabajadores', () => push(context, TripWorkersScreen(trip: t))),
      if (manage && t.isPlanned) ActionItem(Icons.play_arrow, 'Iniciar Viaje', () => _status(t, TripStatus.running)),
      if (manage && t.isRunning) ActionItem(Icons.flag_outlined, 'Terminar Viaje', () => _status(t, TripStatus.finished)),
      if (manage && t.isRunning && t.vehicleState == 'detenido') ActionItem(Icons.report_outlined, 'Indicar causa de detención', () => _detentionCause(t)),
      // Cancelar solo un Planificado; eliminar solo un Cancelado o Terminado (docs/11 §11.67).
      if (manage && t.canCancel && (me.isAdmin || t.createdById == me.userId))
        ActionItem(Icons.cancel_outlined, 'Cancelar Viaje', () => _status(t, TripStatus.cancelled), destructive: true),
      if (manage && t.canDelete)
        ActionItem(Icons.delete_outline, 'Eliminar Viaje', () async {
          if (!await confirmDelete(context, 'el ${t.title.toLowerCase()}', consequences: 'Se borra con sus estados y su recorrido, sin avisar a nadie.')) return;
          if (!mounted) return;
          await context.read<Session>().api.delete('/trips/${t.id}');
          _editable = false;
          if (mounted) Navigator.pop(context, true);
        }, destructive: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LeaveGuard(
      dirty: () => _dirty,
      onSave: () async {
        final t = _view.currentState?.data?.$1;
        return t != null && await _save(t);
      },
      child: AppScaffold(
      title: 'Viaje',
      tab: MainTab.trips,
      actions: _actions,
      body: DataView<(Trip, List<NomenclatorItem>)>(
        what: 'Viaje',
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
              value: _time == null ? '' : time24(_time!.hour, _time!.minute),
              icon: Icons.schedule,
              enabled: edit,
              onTap: edit
                  ? () async {
                      final v = await pickTime24(context, _time ?? const TimeOfDay(hour: 7, minute: 0));
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
            FormText(controller: _observation, label: 'Observación', readOnly: !edit, maxLines: 2, last: true, onChanged: (_) => setState(() {})),
            FormText(label: 'Estado', value: TripStatus.name(t.status), readOnly: true),
            FormText(label: 'Ocupación prevista', value: t.occupancy, readOnly: true),
            if (t.myState != null) FormText(label: 'Mi estado', value: WorkerState.name(t.myState), readOnly: true),
          ]);
        },
      ),
    ),
    );
  }
}

extension on Trip {
  String get updatedKey => '$id|$date|$departureTime|$vehicleTypeId|$observation';
}

/// Un sentido de «Crear Viaje»: su interruptor, Fecha, Hora de salida y Tipo de vehículo.
class _Leg {
  final String direction;
  final String label;
  bool enabled = true;
  DateTime date;
  TimeOfDay time;
  String? vehicleType;

  _Leg(this.direction, this.label, this.date, this.time);

  List<Object?> get snapshot => [enabled, date, time, vehicleType];
}

/// «Crear Viaje» (docs/11 §11.33 y §11.65): Ida y Regreso, cada uno con su
/// interruptor, su Fecha, su Hora de salida (12 h, en un diálogo al tocarla) y
/// su Tipo de vehículo. Por omisión, Ida hoy a las 05:00 p. m. y Regreso
/// mañana a las 06:00 a. m. Se crean viajes independientes.
class PlanTripScreen extends StatefulWidget {
  final String? itineraryId;

  const PlanTripScreen({super.key, this.itineraryId});

  @override
  State<PlanTripScreen> createState() => _PlanTripScreenState();
}

/// Fechas y horas por omisión de «Crear Viaje» (código puro, con pruebas).
({DateTime outboundDate, TimeOfDay outboundTime, DateTime returnDate, TimeOfDay returnTime}) planDefaults(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return (
    outboundDate: today,
    outboundTime: const TimeOfDay(hour: 17, minute: 0),
    returnDate: today.add(const Duration(days: 1)),
    returnTime: const TimeOfDay(hour: 6, minute: 0),
  );
}

class _PlanTripScreenState extends State<PlanTripScreen> {
  Itinerary? _itinerary;
  List<Itinerary> _itineraries = const [];
  List<NomenclatorItem> _types = const [];
  late final List<_Leg> _legs;
  final _observation = TextEditingController();
  List<Object?>? _initial;
  bool _planned = false;

  List<Object?> _snapshot() => [_itinerary?.id, for (final l in _legs) ...l.snapshot, _observation.text];

  bool get _dirty => !_planned && _initial != null && !listEquals(_initial, _snapshot());

  @override
  void initState() {
    super.initState();
    final d = planDefaults(DateTime.now());
    _legs = [_Leg('ida', 'Ida', d.outboundDate, d.outboundTime), _Leg('regreso', 'Regreso', d.returnDate, d.returnTime)];
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
        for (final l in _legs) {
          l.vehicleType = types.firstOrNull?.id;
        }
        _initial = _snapshot();
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<bool> _plan() async {
    final itinerary = _itinerary;
    if (itinerary == null) throw StateError('Elija el itinerario.');
    if (!_legs.any((l) => l.enabled)) throw StateError('Active Ida, Regreso o los dos.');
    final api = context.read<Session>().api;
    final created = <String>[];
    final ok = await runAction(context, label: 'Creando Viaje', () async {
      for (final l in _legs.where((l) => l.enabled)) {
        if (l.vehicleType == null) throw StateError('Elija el tipo de vehículo de ${l.label.toLowerCase()}.');
        final document = await api.post('/trips', resourceData('trips', attributes: {
          'direction': l.direction,
          'date': apiDay(l.date),
          'departureTime': _hhmm(l.time),
          if (_observation.text.trim().isNotEmpty) 'observation': _observation.text.trim(),
        }, relationships: {
          'itinerary': ResourceId('itineraries', itinerary.id),
          'vehicleType': ResourceId('vehicle-types', l.vehicleType!),
        }));
        created.add(document.resource.id);
        // Si uno ya se creó, no se repite al reintentar.
        if (mounted) setState(() => l.enabled = false);
      }
    });
    if (!ok || !mounted || created.isEmpty) return false;
    _planned = true;
    // El formulario sigue mostrando lo guardado: el (primer) viaje creado.
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TripFormScreen(tripId: created.first)), result: true);
    return true;
  }

  Widget _leg(_Leg l) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(children: [
        SwitchListTile(
          value: l.enabled,
          onChanged: (v) => setState(() => l.enabled = v),
          title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          secondary: Icon(l.direction == 'ida' ? Icons.east : Icons.west),
        ),
        if (l.enabled) ...[
          FormText(
            key: ValueKey('${l.direction}${l.date}'),
            label: 'Fecha',
            value: formatDate(l.date),
            icon: Icons.event,
            onTap: () async {
              final today = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: l.date, firstDate: DateTime(today.year, today.month, today.day), lastDate: DateTime(2100));
              if (d != null) setState(() => l.date = d);
            },
          ),
          FormText(
            key: ValueKey('${l.direction}${l.time}'),
            label: 'Hora de salida',
            value: time24(l.time.hour, l.time.minute),
            icon: Icons.schedule,
            onTap: () async {
              final v = await pickTime24(context, l.time);
              if (v != null) setState(() => l.time = v);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: DropdownButtonFormField<String>(
              initialValue: l.vehicleType,
              decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
              items: [for (final v in _types) DropdownMenuItem(value: v.id, child: Text(v.vehicleLabel))],
              onChanged: (v) => setState(() => l.vehicleType = v),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LeaveGuard(
      dirty: () => _dirty,
      onSave: _plan,
      child: AppScaffold.list(
      title: 'Crear Viaje',
      tab: MainTab.trips,
      actions: () => [ActionItem(Icons.save_outlined, 'Guardar', _plan)],
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
        for (final l in _legs) _leg(l),
        FormText(controller: _observation, label: 'Observación', maxLines: 2, last: true),
      ],
    ),
    );
  }
}
