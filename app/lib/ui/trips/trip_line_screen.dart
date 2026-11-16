import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/tracking/tracking_service.dart';
import '../../services/tracking/trip_permissions.dart';
import '../../services/tracking/trip_window.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'trip_card.dart';
import 'trip_form_screen.dart';
import 'trip_permissions_screen.dart';
import 'trip_workers_screen.dart';

/// Línea del recorrido en tiempo real, sin mapa (docs/11 §11.39, §11.46 y
/// §11.65): la línea siempre en el mismo sitio, las paradas en el orden del
/// recorrido con cuántos trabajadores hay en cada una en cada estado (De
/// camino, En la parada, Retrasado, No recogido y Dejado; sin ceros; en la
/// ida y en el regreso), las tarjetas de Sensores y Mi estado (del mismo
/// tamaño) y el vehículo en su tramo. Los trabajadores del viaje deben tener
/// la ubicación activada para verla.
class TripLineScreen extends StatefulWidget {
  final String tripId;

  const TripLineScreen({super.key, required this.tripId});

  @override
  State<TripLineScreen> createState() => _TripLineScreenState();
}

class _TripLineScreenState extends State<TripLineScreen> with WidgetsBindingObserver {
  Trip? _trip;
  TripLive? _live;
  Object? _error;
  TripPermissions? _permissions;
  Timer? _timer;
  String? _departure;

  Session get _session => context.read<Session>();

  /// Viaja en este viaje (es de su itinerario; la parada habitual es opcional).
  Placement? get _membership {
    final trip = _trip;
    if (trip == null) return null;
    return _session.me?.placements.where((p) => p.itineraryId == trip.itineraryId).firstOrNull;
  }

  /// Es trabajador de este viaje (posible sensor): solo a él le obliga la
  /// ubicación; el Administrador y los Jefes que no viajan lo ven sin ella
  /// (docs/11 §11.62).
  bool get _travels => _live != null ? _live!.travels : _membership != null;

  bool? get _locationReady => _permissions?.foreground;

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
        _departure = stops.isEmpty ? null : (trip.outbound ? stops.first.landmark : stops.last.landmark);
      });
      await _rememberWindow(trip);
      await _checkLocation();
      await _refresh();
      _timer?.cancel();
      _timer = Timer.periodic(_session.settings.shortEvery, (_) => _refresh());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Si viaja en él, el viaje entra ya en su ventana de viaje (docs/11 §11.65):
  /// no depende de que la última consulta lo trajera.
  Future<void> _rememberWindow(Trip trip) async {
    final placement = _membership;
    if (placement == null || !trip.isOpen) return;
    await TripWindow.remember(WindowTrip(
      id: trip.id,
      itineraryId: trip.itineraryId,
      itineraryName: trip.itineraryName,
      direction: trip.direction,
      status: trip.status,
      departsAt: trip.departsAt,
      statusChangedAt: trip.statusChangedAt,
      myStopId: placement.stopId,
      myState: trip.myState,
    ));
  }

  Future<void> _checkLocation() async {
    final permissions = await TripPermissions.check();
    if (mounted) setState(() => _permissions = permissions);
    // Dentro de la ventana de viaje (X antes de la salida) arranca el servicio.
    if (permissions.foreground) await _session.maybeStartTracking();
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

  /// Declara su estado a mano (con la parada elegida y la hora de captura).
  Future<void> _report(String state, {String? stopId, List<String>? childIds, String? tripId}) async {
    await _session.api.post('/trips/${tripId ?? widget.tripId}/reports', resourceData('trip-reports', attributes: {
      'events': [
        {
          'kind': 'worker',
          'state': state,
          'stopId': ?(stopId == null ? null : int.tryParse(stopId)),
          if (childIds != null) 'childIds': [for (final id in childIds) int.tryParse(id) ?? 0],
          'capturedAt': DateTime.now().toIso8601String(),
        },
      ],
    }));
    if (childIds != null) await TrackingService.setChildren(childIds);
    TrackingService.syncNow();
    await _refresh();
  }

  /// Parada del recorrido para declarar su estado (por omisión, la próxima sin pasar).
  Future<LiveStop?> _pickStop(String title, {bool pending = true}) async {
    final live = _live;
    if (live == null) return null;
    final options = live.stops.where((s) => !pending || !s.passed).toList();
    if (options.isEmpty) return null;
    if (options.length == 1) return options.first;
    return pickOne<LiveStop>(context, title, options, (s) => s.landmark, subtitle: (s) => s.street ?? '');
  }

  /// Hijos que suben con él (los activos con derecho a viajar).
  Future<List<String>?> _pickChildren() async {
    final children = (await _session.api.getAll('/children', query: {'filter[parent]': _session.me!.userId, 'filter[active]': 'true', 'filter[eligible]': 'true'})).map(Child.from).toList();
    if (children.isEmpty || !mounted) return const [];
    final chosen = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          icon: const Icon(Icons.child_care, size: 32),
          title: '¿Con qué hijos sube?',
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in children)
              CheckboxListTile(
                value: chosen.contains(c.id),
                title: Text(c.fullName),
                onChanged: (v) => setState(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
              ),
          ]),
          buttons: [
            primaryButton(context, 'Confirmar', Icons.check, () => Navigator.pop(context, chosen.toList())),
            cancelButton(context),
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
        builder: (context) => AppDialog(
          icon: const Icon(Icons.block, size: 32),
          title: 'No voy',
          content: const Text('¿Tampoco irá en el regreso?', textAlign: TextAlign.center),
          buttons: [
            dangerButton(context, 'Tampoco en el regreso', Icons.block, () => Navigator.pop(context, true)),
            otherButton(context, 'Solo la ida', Icons.east, () => Navigator.pop(context, false)),
            cancelButton(context),
          ],
        ),
      );
      if (answer == null) return;
      alsoReturn = answer;
    } else if (!await confirm(context, 'No voy', '¿Confirma que no irá en este viaje de regreso?', accept: 'No voy', icon: Icons.block, headerIcon: Icons.block, destructive: true)) {
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
    final mine = _travels && trip.isOpen && _locationReady == true;
    final state = live?.myState;
    final open = state == null || state == WorkerState.onTheWay || state == WorkerState.atStop;
    return [
      if (_travels && _locationReady != true) ActionItem(Icons.my_location, 'Activar ubicación', _enableLocation),
      if ((manage || live?.canManage == true) && live != null && (live.status == TripStatus.running || live.status == TripStatus.planned) && live.nextStopIndex < live.stops.length)
        ActionItem(Icons.where_to_vote, 'Actualizar Viaje: Marcar paso por parada', () => _markPassed(_passTarget(live))),
      // Mi estado, a mano (docs/11 §11.65): en cualquier parada, ida y regreso.
      if (mine && open)
        ActionItem(Icons.where_to_vote_outlined, 'Actualizar Mi estado: En la parada', () async {
          final stop = await _pickStop('¿En qué parada está?');
          if (stop != null) await _report(WorkerState.atStop, stopId: stop.stopId);
        }),
      if (mine && open)
        ActionItem(Icons.directions_bus, 'Actualizar Mi estado: Viajando', () async {
          final stop = await _pickStop('¿En qué parada subió?', pending: false);
          if (stop == null) return;
          final kids = await _pickChildren();
          if (kids != null) await _report(WorkerState.travelling, stopId: stop.stopId, childIds: kids);
        }),
      if (mine && state == WorkerState.travelling)
        ActionItem(Icons.hail, 'Actualizar Mi estado: Dejado', () async {
          final stop = await _pickStop('¿En qué parada se bajó?', pending: false);
          if (stop != null) await _report(WorkerState.dropped, stopId: stop.stopId);
        }),
      if (mine && open) ActionItem(Icons.block, 'Actualizar Mi estado: No voy', _notGoing, destructive: true),
      ActionItem(Icons.groups_outlined, 'Consultar Trabajadores', () => push(context, TripWorkersScreen(trip: trip))),
      ActionItem(Icons.description_outlined, 'Consultar Viaje', () => push(context, TripFormScreen(tripId: trip.id))),
      if (manage && trip.isPlanned && live?.status == TripStatus.planned)
        ActionItem(Icons.play_arrow, 'Actualizar Viaje: Iniciar', () => _setStatus(TripStatus.running, 'Iniciar')),
      if (manage && live?.status == TripStatus.running) ActionItem(Icons.flag_outlined, 'Actualizar Viaje: Terminar', () => _setStatus(TripStatus.finished, 'Terminar')),
    ];
  }

  /// La parada que se marcaría: la próxima (en un viaje Planificado, la salida).
  LiveStop _passTarget(TripLive live) => live.status == TripStatus.planned ? live.stops.first : live.stops[live.nextStopIndex.clamp(0, live.stops.length - 1)];

  /// «Pasó por la parada X» (Jefe o Administrador, docs/11 §11.61): cuenta
  /// como la confirmación de los sensores.
  Future<void> _markPassed(LiveStop stop) async {
    if (!await confirm(context, 'Marcar paso por parada', '¿Marcar que el vehículo pasó por «${stop.landmark}»? Cuenta como la confirmación de los sensores.',
        accept: 'Marcar paso', icon: Icons.where_to_vote, headerIcon: Icons.where_to_vote)) {
      return;
    }
    await _session.api.post('/trips/${widget.tripId}/stop-passes', resourceData('trip-stop-passes', attributes: {'routeIndex': stop.index}));
    await _refresh();
  }

  /// Por qué cada trabajador del viaje es o no sensor (maqueta G23 n.º 8).
  Future<void> _showSensors(TripLive live) async {
    List<TripWorker>? workers;
    try {
      workers = await TripWorker.load(_session.api, widget.tripId);
    } catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final list = workers.where((w) => w.expected || w.state != null).toList()
      ..sort((a, b) => (b.sensor ? 1 : 0).compareTo(a.sensor ? 1 : 0));
    final sensors = list.where((w) => w.sensor).length;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Sensores ($sensors de ${list.length})', style: Theme.of(context).textTheme.titleLarge),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Es sensor quien va en el vehículo (Viajando) y su teléfono envía con GPS.'),
          ),
          for (final w in list)
            InfoCard(
              images: [CardImage(url: w.photoUrl, icon: Icons.person, round: true)],
              title: w.name,
              lines: [w.sensorText(live.outbound)],
              chip: w.sensor ? const Chip2('Sensor', green) : const Chip2('No es sensor', grey),
            ),
        ]),
      ),
    );
  }

  Future<void> _setStatus(String status, String verb) async {
    if (!await confirm(context, 'Actualizar Viaje: $verb', '¿$verb el viaje?', accept: verb, icon: Icons.check)) return;
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
        body: _error != null ? ErrorView(message: errorText(_error), onRetry: _load) : BusyPanel(text: 'Consultando Viaje', onCancel: () => Navigator.maybePop(context)),
      );
    }
    // Ubicación obligatoria solo para los trabajadores del viaje (docs/11 §11.62).
    final permissions = _permissions;
    if (_travels && permissions != null && !permissions.foreground) {
      return AppScaffold.list(title: title, tab: MainTab.trips, actions: _actions, children: [
        TripCard(trip: trip, departure: _departure),
        TripPermissionsCard(permissions: permissions, onChanged: _checkLocation),
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
          if (_travels && permissions != null && !permissions.complete && trip.isOpen) TripPermissionsCard(permissions: permissions, onChanged: _checkLocation),
          if (live == null)
            const SizedBox(height: 240, child: BusyPanel(text: 'Consultando Recorrido'))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              // Las dos tarjetas del mismo tamaño (docs/11 §11.65).
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showSensors(live),
                      child: _Box(icon: Icons.sensors, color: green, label: live.sensors == 1 ? 'Sensor ahora' : 'Sensores ahora', value: '${live.sensors}', detail: 'Ver'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _Box(icon: Icons.person_pin_circle_outlined, color: blue2, label: 'Mi estado', value: WorkerState.name(live.myState), detail: myStateStop(live))),
                ]),
              ),
            ),
            if (live.detentionCause != null || live.longDetention)
              NoticeCard(icon: Icons.report_outlined, title: 'Vehículo detenido', detail: live.detentionCause ?? 'Lleva detenido más de lo normal.', color: amber),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('Recorrido', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))),
            ..._line(live),
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
      final info = <Widget>[];
      if (s.passed && s.passedAt != null) info.add(_tx('${i == 0 ? 'Salió' : 'Pasó'} ${formatTime(s.passedAt)}${s.passedManually ? ' (marcado a mano)' : ''}'));
      final chips = stopCountChips(s.counts);
      if (chips.isNotEmpty) {
        info.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [for (final (l, col) in chips) Chip2(l, col)]),
        ));
      }
      if (last) info.add(_tx('Última parada'));
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
    } else if (live.vehicleState == null) {
      // Sin sensores no se sabe nada del vehículo (docs/11 §11.61).
      head = 'Sin datos del vehículo';
      detail = live.sensors == 0 ? 'Ningún sensor activo todavía' : 'Esperando el primer dato de los sensores';
    } else {
      head = 'En movimiento';
      detail = 'Entre ${from.landmark} y ${to.landmark}';
    }
    if (live.vehicleState != null && live.sensors == 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _tx(head, color: amber, bold: true),
        _tx(detail, color: amber),
        _tx('Último dato de las ${formatTime(live.vehicleSince)}: ahora no hay sensores activos', color: grey),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_tx(head, color: amber, bold: true), _tx(detail, color: amber)]);
  }
}

/// La parada de «Mi estado» (docs/11 §11.65): en todos los estados salvo
/// Viajando; en Dejado, donde se le dejó.
String myStateStop(TripLive live) {
  if (live.myState == null || live.myState == WorkerState.travelling) return '';
  if (live.myState == WorkerState.notGoing) return '';
  return live.myStopName ?? live.stops.where((s) => s.stopId == live.myStopId).firstOrNull?.landmark ?? '';
}

/// Cantidades de una parada (docs/11 §11.65): De camino, En la parada,
/// Retrasado, No recogido y Dejado, con su plural y sin ceros.
List<(String, Color)> stopCountChips(Map<String, int> counts) => [
      for (final (state, color) in const [
        (WorkerState.onTheWay, grey),
        (WorkerState.atStop, blue2),
        (WorkerState.late, purple),
        (WorkerState.leftBehind, red),
        (WorkerState.dropped, green),
      ])
        if ((counts[state] ?? 0) > 0) ('${WorkerState.count(state, counts[state]!)}: ${counts[state]}', color),
    ];

Widget _tx(String s, {Color? color, bool bold = false}) => Text(s, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

/// Tarjeta de Sensores o Mi estado: ícono, etiqueta, valor y detalle, con la
/// misma forma (y el mismo tamaño) las dos.
class _Box extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;

  const _Box({required this.icon, required this.color, required this.label, required this.value, this.detail = ''});

  @override
  Widget build(BuildContext context) {
    final c = readable(context, color);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color)),
      child: Row(children: [
        Icon(icon, color: c, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: TextStyle(fontSize: 12, color: c)),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(detail, style: TextStyle(fontSize: 12, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
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
            Positioned(top: 2, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: t.colorScheme.surface, shape: BoxShape.circle, border: Border.all(color: c, width: 5)))),
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
                if (mine) ...[const SizedBox(width: 6), const Chip2('Parada habitual', green)],
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
