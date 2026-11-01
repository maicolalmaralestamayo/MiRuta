import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Crear o editar viajes (docs/09 §23). Al crear se eligen varios
/// itinerarios y se marcan en el almanaque uno o varios días; se crea un viaje
/// por día e itinerario (todos o ninguno), cada itinerario con su vehículo y
/// su chofer. Las horas de ida y de regreso valen para cada día; si la de
/// regreso es anterior a la de ida, el regreso es al día siguiente.
class TripFormScreen extends StatefulWidget {
  final Trip? trip;

  const TripFormScreen({super.key, this.trip});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

/// Vehículo y chofer de un itinerario.
class _Row {
  String? vehicleId;
  String? driverId;
}

class _TripFormScreenState extends State<TripFormScreen> {
  List<Itinerary> _itineraries = [];
  List<Vehicle> _vehicles = [];
  List<(String, String)> _drivers = [];

  /// Itinerarios elegidos, en el orden de la lista.
  final List<String> _itineraryIds = [];
  final Map<String, _Row> _rows = {};

  /// Días marcados (al editar, uno solo).
  final Set<DateTime> _days = {};
  TimeOfDay? _outboundTime;
  TimeOfDay? _returnTime;
  String _status = TripStatus.unconfirmed;
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  /// Errores del servidor por itinerario (solapes, con el día).
  final Map<String, List<String>> _rowErrors = {};

  bool get _editing => widget.trip != null;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    if (trip != null) {
      _itineraryIds.add(trip.itineraryId);
      _rows[trip.itineraryId] = _Row()
        ..vehicleId = trip.vehicleId
        ..driverId = trip.driverId;
      _days.add(_dayOf(trip.departsAt));
      _outboundTime = TimeOfDay.fromDateTime(trip.departsAt);
      _returnTime = TimeOfDay.fromDateTime(trip.returnsAt);
      _status = trip.status;
    } else {
      _outboundTime = const TimeOfDay(hour: 17, minute: 0);
      _returnTime = const TimeOfDay(hour: 6, minute: 30);
    }
    _load();
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

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
      if (!mounted) return;
      setState(() {
        _itineraries = itineraries;
        _vehicles = vehicles;
        _drivers = drivers;
        if (_itineraryIds.isEmpty && itineraries.length == 1) _toggleItinerary(itineraries.first.id, true);
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void _toggleItinerary(String id, bool selected) {
    if (selected) {
      if (_editing) {
        final previous = _itineraryIds.isEmpty ? null : _rows[_itineraryIds.first];
        _itineraryIds
          ..clear()
          ..add(id);
        _rows
          ..clear()
          ..[id] = previous ?? _Row();
      } else if (!_itineraryIds.contains(id)) {
        _itineraryIds.add(id);
        _rows[id] = _Row();
        // Orden de la lista de itinerarios.
        final order = {for (var i = 0; i < _itineraries.length; i++) _itineraries[i].id: i};
        _itineraryIds.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));
      }
    } else {
      _itineraryIds.remove(id);
      _rows.remove(id);
    }
    _rowErrors.clear();
  }

  String _itineraryName(String id) => _itineraries.where((i) => i.id == id).firstOrNull?.name ?? 'Itinerario';

  String _vehicleLabel(Vehicle v) => '${v.vehicleType?.name ?? ''} ${formatPlate(v.plate)} (${plural(v.totalCapacity, 'plaza', 'plazas')})'.trim();

  (DateTime, DateTime) _times(DateTime day) {
    final out = _outboundTime!;
    final ret = _returnTime!;
    final departs = DateTime(day.year, day.month, day.day, out.hour, out.minute);
    var returns = DateTime(day.year, day.month, day.day, ret.hour, ret.minute);
    // Si la hora de regreso es anterior a la de ida, el regreso es al día siguiente.
    if (!returns.isAfter(departs)) returns = DateTime(day.year, day.month, day.day + 1, ret.hour, ret.minute);
    return (departs, returns);
  }

  bool get _returnsNextDay {
    final out = _outboundTime;
    final ret = _returnTime;
    if (out == null || ret == null) return false;
    return ret.hour * 60 + ret.minute <= out.hour * 60 + out.minute;
  }

  /// Faltantes o repetidos de cada fila (vehículo o chofer en dos itinerarios a la vez).
  String? _rowProblem(String itineraryId) {
    final row = _rows[itineraryId]!;
    if (row.vehicleId == null && row.driverId == null) return _submitted ? 'Elija el vehículo y el chofer.' : null;
    if (row.vehicleId == null) return _submitted ? 'Elija el vehículo.' : null;
    if (row.driverId == null) return _submitted ? 'Elija el chofer.' : null;
    final others = _itineraryIds.where((id) => id != itineraryId).map((id) => _rows[id]!);
    if (others.any((o) => o.vehicleId == row.vehicleId)) return 'El vehículo está elegido también para otro itinerario.';
    if (others.any((o) => o.driverId == row.driverId)) return 'El chofer está elegido también para otro itinerario.';
    return null;
  }

  Map<String, dynamic> _data(String itineraryId, DateTime day) {
    final (departs, returns) = _times(day);
    final row = _rows[itineraryId]!;
    return resourceData('trips', id: widget.trip?.id, attributes: {
      'departsAt': departs.toUtc().toIso8601String(),
      'returnsAt': returns.toUtc().toIso8601String(),
      'status': _status,
    }, relationships: {
      'itinerary': ResourceId('itineraries', itineraryId),
      'vehicle': ResourceId('vehicles', row.vehicleId!),
      'driver': ResourceId('drivers', row.driverId!),
    })['data'] as Map<String, dynamic>;
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _error = null;
      _rowErrors.clear();
    });
    if (_itineraryIds.isEmpty || _days.isEmpty || _outboundTime == null || _returnTime == null || _itineraryIds.any((id) => _rowProblem(id) != null)) {
      setState(() => _error = 'Revise los campos marcados.');
      return;
    }
    final days = _days.toList()..sort();
    final count = days.length * _itineraryIds.length;
    if (!_editing &&
        !await confirm(
          context,
          'Crear viajes',
          'Se crearán ${plural(count, 'viaje', 'viajes')} '
              '(${plural(days.length, 'día', 'días')} × ${plural(_itineraryIds.length, 'itinerario', 'itinerarios')}). ¿Crearlos?',
          accept: count == 1 ? 'Crear viaje' : 'Crear viajes',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    // Qué itinerario y qué día es cada operación, para señalar los solapes.
    final targets = <(String, DateTime)>[
      for (final itineraryId in _itineraryIds)
        for (final day in days) (itineraryId, day),
    ];
    try {
      final api = context.api;
      if (_editing) {
        await api.patch('/trips/${widget.trip!.id}', {'data': _data(targets.first.$1, targets.first.$2)});
      } else {
        // Todos o ninguno.
        await api.atomicOperations([for (final (itineraryId, day) in targets) {'op': 'add', 'data': _data(itineraryId, day)}]);
      }
      if (mounted) {
        showMessage(context, _editing ? 'Viaje guardado' : (count == 1 ? 'Viaje creado' : plural(count, 'viaje creado', 'viajes creados')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      final overlaps = error.errors.where((e) => e.code == 'TRIP_OVERLAP').toList();
      setState(() {
        if (overlaps.isEmpty) {
          _error = error.message;
          return;
        }
        for (final e in overlaps) {
          final index = int.tryParse(RegExp(r'/atomic:operations/(\d+)').firstMatch(e.pointer ?? '')?.group(1) ?? '');
          final target = index != null && index < targets.length ? targets[index] : targets.first;
          final day = e.meta['departsAt'] == null ? target.$2 : DateTime.parse('${e.meta['departsAt']}').toLocal();
          _rowErrors.putIfAbsent(target.$1, () => []).add('${formatDate(day)}: ${e.message}');
        }
        _error = _editing
            ? 'El viaje se solapa con otro.'
            : 'Hay ${plural(overlaps.length, 'solape', 'solapes')} (señalados en cada itinerario). No se creó ningún viaje.';
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _itineraryField() {
    final error = _submitted && _itineraryIds.isEmpty ? (_editing ? 'Elija el itinerario.' : 'Elija uno o varios itinerarios.') : null;
    if (_editing) {
      return DropdownButtonFormField<String>(
        initialValue: _itineraryIds.firstOrNull,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'Itinerario', errorText: error),
        items: [for (final i in _itineraries) DropdownMenuItem(value: i.id, child: Text(i.name))],
        onChanged: (value) => setState(() => _toggleItinerary(value!, true)),
      );
    }
    return InputDecorator(
      isEmpty: false,
      decoration: InputDecoration(labelText: 'Itinerarios', errorText: error),
      child: _itineraries.isEmpty
          ? const Text('Cargando…')
          : Wrap(spacing: 8, runSpacing: 4, children: [
              for (final i in _itineraries)
                FilterChip(
                  label: Text(i.name),
                  selected: _itineraryIds.contains(i.id),
                  onSelected: (selected) => setState(() => _toggleItinerary(i.id, selected)),
                ),
            ]),
    );
  }

  Widget _row(String itineraryId) {
    final row = _rows[itineraryId]!;
    final problem = _rowProblem(itineraryId);
    final serverErrors = _rowErrors[itineraryId] ?? const [];
    final vehicle = _vehicles.where((v) => v.id == row.vehicleId).firstOrNull;
    final errorColor = Theme.of(context).colorScheme.error;
    final hasError = problem != null || serverErrors.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: hasError ? RoundedRectangleBorder(side: BorderSide(color: errorColor), borderRadius: BorderRadius.circular(12)) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_itineraryName(itineraryId), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('vehicle-$itineraryId'),
            initialValue: row.vehicleId,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Vehículo', errorText: _submitted && row.vehicleId == null ? 'Elija el vehículo.' : null),
            items: [for (final v in _vehicles) DropdownMenuItem(value: v.id, child: Text(_vehicleLabel(v), overflow: TextOverflow.ellipsis))],
            onChanged: (value) => setState(() {
              row.vehicleId = value;
              // Se propone el chofer habitual del vehículo.
              final habitual = _vehicles.firstWhere((v) => v.id == value).driverId;
              if (habitual != null && _drivers.any((d) => d.$1 == habitual)) row.driverId = habitual;
              _rowErrors.remove(itineraryId);
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            // La clave cambia con el chofer para que tome el habitual propuesto.
            key: ValueKey('driver-$itineraryId-${row.driverId}'),
            initialValue: _drivers.any((d) => d.$1 == row.driverId) ? row.driverId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Chofer', errorText: _submitted && row.driverId == null ? 'Elija el chofer.' : null),
            items: [
              for (final d in _drivers)
                DropdownMenuItem(value: d.$1, child: Text(vehicle?.driverId == d.$1 ? '${d.$2} (habitual)' : d.$2, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() {
              row.driverId = value;
              _rowErrors.remove(itineraryId);
            }),
          ),
          if (problem != null && (row.vehicleId != null && row.driverId != null))
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(problem, style: TextStyle(color: errorColor))),
          for (final e in serverErrors)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber, size: 18, color: errorColor),
                const SizedBox(width: 6),
                Expanded(child: Text(e, style: TextStyle(color: errorColor))),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _days.length;
    final count = days * _itineraryIds.length;
    final dayError = _submitted && _days.isEmpty ? (_editing ? 'Elija el día.' : 'Marque uno o varios días.') : null;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar viaje' : 'Nuevo viaje')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _itineraryField(),
        const SizedBox(height: 16),
        if (_editing)
          DateField(
            label: 'Día',
            value: _days.firstOrNull,
            errorText: dayError,
            onChanged: (day) => setState(() {
              _days
                ..clear()
                ..add(_dayOf(day));
            }),
          )
        else
          InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: days == 0 ? 'Días' : 'Días (${plural(days, 'marcado', 'marcados')})',
              errorText: dayError,
            ),
            child: _MultiDayCalendar(
              selected: _days,
              firstDay: _dayOf(DateTime.now()),
              onToggle: (day) => setState(() {
                _days.contains(day) ? _days.remove(day) : _days.add(day);
                _rowErrors.clear();
              }),
              onClear: () => setState(_days.clear),
            ),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TimeField(
              label: 'Viaje de ida',
              value: _outboundTime,
              errorText: _submitted && _outboundTime == null ? 'Elija la hora.' : null,
              onChanged: (time) => setState(() => _outboundTime = time),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TimeField(
              label: 'Viaje de regreso',
              value: _returnTime,
              errorText: _submitted && _returnTime == null ? 'Elija la hora.' : null,
              onChanged: (time) => setState(() => _returnTime = time),
            ),
          ),
        ]),
        if (_returnsNextDay)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('El viaje de regreso es al día siguiente.', style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: [
            for (final status in [TripStatus.unconfirmed, TripStatus.confirmed, if (_editing) TripStatus.completed, if (_editing) TripStatus.cancelled])
              DropdownMenuItem(value: status, child: Text(TripStatus.label(status))),
          ],
          onChanged: (value) => setState(() => _status = value!),
        ),
        if (_itineraryIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final id in _itineraryIds) _row(id),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!_editing && count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('Se crearán ${plural(count, 'viaje', 'viajes')}.', style: Theme.of(context).textTheme.titleSmall),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const BusyIndicator() : Icon(_editing ? Icons.save : Icons.add),
          label: Text(_editing ? 'Guardar viaje' : (count == 1 ? 'Crear viaje' : 'Crear viajes')),
        ),
      ]),
    );
  }
}

/// Almanaque mensual en el que se marcan uno o varios días, seguidos o sueltos.
class _MultiDayCalendar extends StatefulWidget {
  final Set<DateTime> selected;
  final DateTime firstDay;
  final ValueChanged<DateTime> onToggle;
  final VoidCallback onClear;

  const _MultiDayCalendar({required this.selected, required this.firstDay, required this.onToggle, required this.onClear});

  @override
  State<_MultiDayCalendar> createState() => _MultiDayCalendarState();
}

class _MultiDayCalendarState extends State<_MultiDayCalendar> {
  static const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  static const _weekdays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  late DateTime _month = DateTime(widget.firstDay.year, widget.firstDay.month);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = first.weekday - 1; // lunes = 0
    final canGoBack = DateTime(_month.year, _month.month).isAfter(DateTime(widget.firstDay.year, widget.firstDay.month));
    final cells = <Widget>[
      for (final w in _weekdays) Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall)),
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        Builder(builder: (context) {
          final day = DateTime(_month.year, _month.month, d);
          final enabled = !day.isBefore(widget.firstDay);
          final selected = widget.selected.contains(day);
          return Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: selected ? scheme.primary : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? () => widget.onToggle(day) : null,
                child: Center(
                  child: Text(
                    '$d',
                    style: TextStyle(
                      color: selected ? scheme.onPrimary : (enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.35)),
                      fontWeight: selected ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(
          tooltip: 'Mes anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: canGoBack ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null,
        ),
        Expanded(child: Text('${_months[_month.month - 1]} de ${_month.year}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall)),
        IconButton(
          tooltip: 'Mes siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cells,
      ),
      if (widget.selected.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: widget.onClear, icon: const Icon(Icons.clear_all), label: const Text('Desmarcar los días')),
        ),
    ]);
  }
}
