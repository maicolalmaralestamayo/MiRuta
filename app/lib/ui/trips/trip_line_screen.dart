import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/tracking/tracking_service.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'trip_card.dart';
import 'trip_form_screen.dart';
import 'trip_workers_screen.dart';

/// Línea del recorrido en tiempo real, sin mapa (docs/11 §11.39 y §11.46,
/// maquetas G17): la línea siempre en el mismo sitio, las paradas en el
/// orden del recorrido, las cantidades (sin ceros), los sensores destacados
/// y «Mi estado». Para verla hace falta tener la ubicación activada.
class TripLineScreen extends StatefulWidget {
  final String tripId;

  const TripLineScreen({super.key, required this.tripId});

  @override
  State<TripLineScreen> createState() => _TripLineScreenState();
}

class _TripLineScreenState extends State<TripLineScreen> with WidgetsBindingObserver {
  Trip? _trip;
  TripLive? _live;
  List<Stop> _stops = const [];
  Object? _error;
  bool? _locationReady;
  Timer? _timer;
  String? _departure;

  Session get _session => context.read<Session>();

  /// Viaja en este viaje (tiene parada en su itinerario).
  Placement? get _membership {
    final trip = _trip;
    if (trip == null) return null;
    return _session.me?.placements.where((p) => p.itineraryId == trip.itineraryId && p.stopId != null).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocation();
      _refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final api = _session.api;
    try {
      final trip = Trip.from((await api.get('/trips/${widget.tripId}', query: {'include': 'itinerary,vehicleType'})).resource);
      final stops = (await api.getAll('/stops', query: {'filter[itinerary]': trip.itineraryId, 'sort': 'position'})).map(Stop.from).toList();
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _stops = stops;
        _departure = stops.isEmpty ? null : (trip.outbound ? stops.first.landmark : stops.last.landmark);
      });
      await _checkLocation();
      await _refresh();
      final every = _session.settings.duration('frecuencia_calculo');
      _timer?.cancel();
      _timer = Timer.periodic(every < const Duration(seconds: 5) ? const Duration(seconds: 5) : every, (_) => _refresh());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _checkLocation() async {
    final ready = await TrackingService.locationReady();
    if (mounted) setState(() => _locationReady = ready);
    if (ready) _startTracking();
  }

  /// Desde «Anticipación viaje» antes de la salida calcula su estado.
  Future<void> _startTracking() async {
    final trip = _trip;
    final m = _membership;
    if (trip == null || m == null || !trip.isOpen) return;
    if (DateTime.now().isBefore(trip.departsAt.subtract(_session.settings.duration('anticipacion_viaje')))) return;
    try {
      await TrackingService.start(trip: trip, stops: _stops, myStopId: m.stopId!, settings: _session.settings);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final live = TripLive.from((await _session.api.get('/trips/${widget.tripId}/live')).resource);
      if (mounted) {
        setState(() {
          _live = live;
          _error = null;
        });
      }
      if (live.status == TripStatus.finished || live.status == TripStatus.cancelled) _timer?.cancel();
    } catch (error) {
      if (mounted && _live == null) setState(() => _error = error);
    }
  }

  // Opciones del trabajador

  Future<void> _report(String state, {List<String>? childIds, String? tripId}) async {
    await _session.api.post('/trips/${tripId ?? widget.tripId}/reports', resourceData('trip-reports', attributes: {
      'workerState': state,
      if (childIds != null) 'childIds': [for (final id in childIds) int.tryParse(id) ?? 0],
      'reportedAt': DateTime.now().toIso8601String(),
    }));
    if (childIds != null) await TrackingService.setChildren(childIds);
    if (mounted) showMessage(context, 'Su estado: ${WorkerState.name(state)}.');
    await _refresh();
  }

  /// Hijos que suben con él (los activos con derecho a viajar).
  Future<List<String>?> _pickChildren() async {
    final children = (await _session.api.getAll('/children', query: {'filter[parent]': _session.me!.userId, 'filter[active]': 'true', 'filter[eligible]': 'true'})).map(Child.from).toList();
    if (children.isEmpty || !mounted) return const [];
    final chosen = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          icon: const Icon(Icons.child_care, size: 32),
          title: const Text('¿Con qué hijos sube?', textAlign: TextAlign.center),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in children)
              CheckboxListTile(
                value: chosen.contains(c.id),
                title: Text(c.fullName),
                onChanged: (v) => setState(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
              ),
          ]),
          actions: [
            cancelButton(context),
            FilledButton.icon(onPressed: () => Navigator.pop(context, chosen.toList()), icon: const Icon(Icons.check), label: const Text('Aceptar')),
          ],
        ),
      ),
    );
  }

  Future<void> _notGoing() async {
    final trip = _trip!;
    var alsoReturn = false;
    if (trip.outbound) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.block, size: 32),
          title: const Text('No voy en este viaje', textAlign: TextAlign.center),
          content: const Text('¿Tampoco irá en el regreso?', textAlign: TextAlign.center),
          actions: [
            cancelButton(context, label: 'Volver', icon: Icons.arrow_back),
            TextButton.icon(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.east), label: const Text('Solo la ida')),
            FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.block), label: const Text('Tampoco')),
          ],
        ),
      );
      if (answer == null) return;
      alsoReturn = answer;
    } else if (!await confirm(context, 'No voy en este viaje', '¿Confirma que no irá en este viaje de regreso?', accept: 'No voy', icon: Icons.block, headerIcon: Icons.block, cancel: 'Volver', cancelIcon: Icons.arrow_back)) {
      return;
    }
    await _report(WorkerState.notGoing);
    if (alsoReturn) {
      final back = (await _session.api.getAll('/trips', query: {'filter[itinerary]': trip.itineraryId, 'filter[date]': apiDay(trip.date), 'filter[direction]': 'regreso'})).map(Trip.from).toList();
      for (final t in back.where((t) => t.isOpen)) {
        await _report(WorkerState.notGoing, tripId: t.id);
      }
    }
  }

  List<ActionItem> _actions() {
    final trip = _trip;
    final live = _live;
    if (trip == null) return const [];
    final me = _session.me!;
    final manage = me.isAdmin || me.isChiefOf(trip.itineraryId);
    final mine = _membership != null && trip.isOpen && _locationReady == true;
    final state = live?.myState;
    final first = _stops.isEmpty ? 'de salida' : _stops.first.landmark;
    return [
      if (_locationReady != true) ActionItem(Icons.my_location, 'Activar ubicación', _enableLocation),
      if (mine && trip.outbound && (state == null || state == WorkerState.onTheWay || state == WorkerState.notGoing))
        ActionItem(Icons.where_to_vote_outlined, 'Estoy en la parada $first', () async {
          final kids = await _pickChildren();
          if (kids != null) await _report(WorkerState.atStop, childIds: kids);
        }),
      if (mine && trip.outbound && state == WorkerState.travelling) ActionItem(Icons.hail, 'Me bajé en mi parada', () => _report(WorkerState.dropped)),
      if (mine && !trip.outbound && (state == null || state == WorkerState.onTheWay || state == WorkerState.notGoing))
        ActionItem(Icons.where_to_vote_outlined, 'Estoy en mi parada', () => _report(WorkerState.atStop)),
      if (mine && !trip.outbound && state != WorkerState.pickedUp)
        ActionItem(Icons.directions_bus, 'Ya me recogieron', () async {
          final kids = await _pickChildren();
          if (kids != null) await _report(WorkerState.pickedUp, childIds: kids);
        }),
      if (mine && state != WorkerState.notGoing && state != WorkerState.dropped && state != WorkerState.pickedUp && state != WorkerState.travelling)
        ActionItem(Icons.block, 'No voy en este viaje', _notGoing, destructive: true),
      ActionItem(Icons.groups_outlined, 'Trabajadores', () => push(context, TripWorkersScreen(trip: trip))),
      ActionItem(Icons.description_outlined, 'Datos del viaje', () => push(context, TripFormScreen(tripId: trip.id))),
      if (manage && trip.isPlanned && live?.status == TripStatus.planned)
        ActionItem(Icons.play_arrow, 'Empezar viaje', () => _setStatus(TripStatus.running, 'Empezar')),
      if (manage && live?.status == TripStatus.running) ActionItem(Icons.flag_outlined, 'Terminar viaje', () => _setStatus(TripStatus.finished, 'Terminar')),
    ];
  }

  Future<void> _setStatus(String status, String verb) async {
    if (!await confirm(context, verb, '¿$verb el viaje?', accept: verb, icon: Icons.check)) return;
    await _session.api.patch('/trips/${widget.tripId}', resourceData('trips', id: widget.tripId, attributes: {'status': status}));
    await _refresh();
  }

  Future<void> _enableLocation() async {
    await TrackingService.requestLocation();
    await _checkLocation();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final title = trip?.title ?? 'Viaje';
    if (trip == null) {
      return AppScaffold(
        title: title,
        tab: MainTab.trips,
        body: _error != null ? ErrorView(message: errorText(_error), onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    // Ubicación obligatoria para quien viaja (docs/11 §11.41).
    if (_membership != null && _locationReady == false) {
      return AppScaffold.list(title: title, tab: MainTab.trips, actions: _actions, children: [
        TripCard(trip: trip, departure: _departure),
        NoticeCard(
          icon: Icons.location_off,
          title: 'Active la ubicación',
          detail: 'Para ver el estado del viaje y la línea del recorrido, MiRuta necesita la ubicación (GPS). '
              'Con ella calcula su estado en el teléfono y solo envía los cambios.',
          buttonIcon: Icons.my_location,
          buttonText: 'Activar ubicación',
          onPressed: _enableLocation,
          color: red,
        ),
      ]);
    }
    final live = _live;
    return AppScaffold(
      title: title,
      tab: MainTab.trips,
      actions: _actions,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          TripCard(trip: Trip(
            id: trip.id,
            direction: trip.direction,
            date: trip.date,
            departureTime: trip.departureTime,
            departsAt: trip.departsAt,
            status: live?.status ?? trip.status,
            statusChangedAt: trip.statusChangedAt,
            itineraryId: trip.itineraryId,
            itineraryName: trip.itineraryName,
            vehicleTypeName: trip.vehicleTypeName,
            expectedPassengers: live?.expectedPassengers ?? trip.expectedPassengers,
            capacity: live?.capacity ?? trip.capacity,
          ), departure: _departure),
          if (live == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                Expanded(child: _Box(icon: Icons.sensors, color: green, big: '${live.sensors}', small: 'sensores ahora', bigFirst: true)),
                const SizedBox(width: 8),
                Expanded(child: _Box(icon: Icons.person_pin_circle_outlined, color: blue2, big: WorkerState.name(live.myState), small: 'Mi estado')),
              ]),
            ),
            if (live.detentionCause != null || live.longDetention)
              NoticeCard(icon: Icons.report_outlined, title: 'Vehículo detenido', detail: live.detentionCause ?? 'Lleva detenido más de lo normal.', color: amber),
            const Center(child: Padding(padding: EdgeInsets.only(top: 14, bottom: 6), child: Text('Recorrido', style: TextStyle(color: navyText, fontWeight: FontWeight.w600)))),
            ..._line(live),
            _bottomCard(live),
          ],
        ]),
      ),
    );
  }

  /// Paradas en el orden del recorrido y el vehículo en su tramo.
  List<Widget> _line(TripLive live) {
    final stops = live.stops;
    final widgets = <Widget>[];
    final running = live.status == TripStatus.running;
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final position = live.outbound ? i + 1 : stops.length - i;
      final last = i == stops.length - 1;
      final c = s.counts;
      final info = <Widget>[];
      if (s.passed && s.passedAt != null) info.add(_tx('${i == 0 ? 'Salió' : 'Pasó'} ${formatTime(s.passedAt)}'));
      final chips = <(String, int, Color)>[];
      if (live.outbound) {
        if (!s.passed) chips.addAll([('En la parada', c[WorkerState.atStop] ?? 0, blue2), ('De camino', c[WorkerState.onTheWay] ?? 0, grey)]);
        chips.add(('Dejados', c[WorkerState.dropped] ?? 0, green));
      } else if (s.passed) {
        chips.addAll([('Botados', c[WorkerState.leftBehind] ?? 0, red), ('Dormidos', c[WorkerState.late] ?? 0, purple)]);
      } else {
        chips.addAll([('En la parada', c[WorkerState.atStop] ?? 0, blue2), ('De camino', c[WorkerState.onTheWay] ?? 0, grey)]);
      }
      if (chips.any((x) => x.$2 > 0)) {
        info.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [for (final (l, n, col) in chips) if (n > 0) Chip2('$l: $n', col)]),
        ));
      }
      if (last) info.add(_tx(live.outbound ? 'Última parada' : 'Parada final: se bajan todos'));
      // El vehículo va entre la última pasada y la próxima.
      final busHere = running && s.passed && (i + 1 < stops.length ? !stops[i + 1].passed : false);
      widgets.add(_LineStop(
        name: '$position. ${s.landmark}',
        info: info,
        passed: s.passed,
        first: i == 0,
        last: last,
        mine: s.mine,
        bus: busHere ? _busText(live, s, stops[i + 1]) : null,
      ));
    }
    return widgets;
  }

  Widget _busText(TripLive live, LiveStop from, LiveStop to) {
    final stopped = live.vehicleState == 'detenido';
    final String head;
    final String detail;
    if (stopped && live.vehicleAtStop) {
      head = live.outbound ? 'Dejando' : 'Recogiendo';
      detail = 'En la parada ${to.landmark}';
    } else if (stopped) {
      head = 'Detenido${live.vehicleSince == null ? '' : ' desde las ${formatTime(live.vehicleSince)}'}';
      detail = live.detentionCause ?? 'En el trayecto, entre ${from.landmark} y ${to.landmark}';
    } else {
      head = live.vehicleState == null ? 'Sin datos del vehículo' : 'En movimiento';
      detail = 'Entre ${from.landmark} y ${to.landmark}';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_tx(head, color: amber, bold: true), _tx(detail, color: amber)]);
  }

  Widget _bottomCard(TripLive live) {
    final String big;
    final String title;
    final String detail;
    if (live.outbound && live.status == TripStatus.planned) {
      final waiting = live.stops.isEmpty ? 0 : (live.stops.first.counts[WorkerState.atStop] ?? 0);
      big = '$waiting';
      title = 'Esperando en ${live.stops.isEmpty ? 'la primera parada' : live.stops.first.landmark}';
      detail = '${plural(live.expectedPassengers, 'trabajador esperado', 'trabajadores esperados')}${live.notGoing > 0 ? ' • ${live.notGoing} no van' : ''}';
    } else {
      big = '${live.inVehicleWorkers + live.inVehicleChildren}';
      title = live.outbound ? 'Viajando' : 'Recogidos';
      detail = '${plural(live.inVehicleWorkers, 'trabajador', 'trabajadores')} y ${plural(live.inVehicleChildren, 'niño', 'niños')} en el vehículo'
          '${live.capacity == null ? '' : ' • capacidad ${live.capacity}'}';
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: const Color(0xFFE8F5E9),
      shape: RoundedRectangleBorder(side: const BorderSide(color: green, width: 1.5), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.directions_bus, color: green, size: 30),
          const SizedBox(width: 12),
          Text(big, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: green)),
              Text(detail, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

const navyText = Color(0xFF000080);

Widget _tx(String s, {Color? color, bool bold = false}) => Text(s, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

class _Box extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String big;
  final String small;
  final bool bigFirst;

  const _Box({required this.icon, required this.color, required this.big, required this.small, this.bigFirst = false});

  @override
  Widget build(BuildContext context) {
    final bigText = Text(big, style: TextStyle(fontSize: bigFirst ? 26 : 16, fontWeight: FontWeight.w800, color: color, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis);
    final smallText = Text(small, style: TextStyle(fontSize: 12, color: color));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color)),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: bigFirst ? [bigText, smallText] : [smallText, bigText])),
      ]),
    );
  }
}

/// Una parada en la línea (la línea va siempre en el mismo sitio).
class _LineStop extends StatelessWidget {
  final String name;
  final List<Widget> info;
  final bool passed;
  final bool first;
  final bool last;
  final Widget? bus;
  final bool mine;

  const _LineStop({required this.name, required this.info, this.passed = false, this.first = false, this.last = false, this.bus, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const grey9 = Color(0xFF9E9E9E);
    final c = passed ? grey9 : t.colorScheme.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 40,
          child: Stack(alignment: Alignment.topCenter, children: [
            if (!(first && last))
              Positioned(
                top: first ? 12 : 0,
                bottom: last ? null : 0,
                height: last ? 12 : null,
                child: Container(width: 6, color: passed && bus == null ? grey9 : (passed ? grey9 : t.colorScheme.primary)),
              ),
            Positioned(top: 2, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: c, width: 5)))),
            if (bus != null)
              Positioned(
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: t.colorScheme.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.directions_bus, size: 22, color: Colors.black),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12, right: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: passed ? grey : null))),
                if (mine) ...[const SizedBox(width: 6), const Chip2('Mi parada', green)],
              ]),
              const SizedBox(height: 2),
              ...info,
              if (bus != null) ...[const SizedBox(height: 10), bus!],
            ]),
          ),
        ),
      ]),
    );
  }
}
