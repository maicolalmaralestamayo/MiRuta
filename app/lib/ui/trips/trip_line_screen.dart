import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/busy_scope.dart';
import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../core/server_clock.dart';
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

/// «Ver recorrido» (docs/11 §11.39, §11.46, §11.65 y §11.67), sin mapa:
/// - la tarjeta del viaje en 3 líneas, con el icono de la app;
/// - la tarjeta pequeña de Sensores (icono y cantidad) y la de su estado
///   (icono a la izquierda; a la derecha el estado, «[parada] • [Detenido |
///   En movimiento] • [velocidad]» y «[coordenadas] • [fecha y hora]» de la
///   última ubicación), calculados en el teléfono; antes de Viajando son los
///   suyos y desde Viajando, los del vehículo; cada uno ve solo los suyos;
/// - la línea del recorrido con todas las paradas a la misma distancia, cada
///   una con su estado (En espera, Recogida, Volada, Omitida) y las cantidades
///   de trabajadores por estado (sin ceros; sin Viajando; en la ida sin los
///   Dejados y en el regreso sin los En Parada), y el vehículo en medio del
///   tramo entre la última parada que dejó y la siguiente (o sobre la parada
///   si está detenido en ella).
/// Disponible desde que el viaje está Planificado; quien viaja en él debe
/// tener la ubicación activada (y al abrirla empieza ya su ventana de viaje).
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

  /// Lo calculado en el teléfono para la tarjeta de estado (del servicio de la ventana de viaje).
  MyMotion? _motion;

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
    TrackingService.myMotion.addListener(_onMotion);
    _load();
  }

  void _onMotion() {
    if (mounted) setState(() => _motion = TrackingService.myMotion.value);
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
    TrackingService.myMotion.removeListener(_onMotion);
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
    _motion = await TrackingService.lastMotion(trip.id);
    await TripWindow.remember(openNow: true, WindowTrip(
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
      final resource = (await _session.api.get('/trips/${widget.tripId}/live')).resource;
      await ServerClock.learn(resource.attributes['serverTime']?.toString());
      final live = TripLive.from(resource);
      // Mientras la tiene abierta, su ventana de viaje sigue adelantada (docs/11 §11.67).
      final trip = _trip;
      if (trip != null && _membership != null && (live.status == TripStatus.planned || live.status == TripStatus.running)) {
        await TripWindow.remember(openNow: true, WindowTrip(
          id: trip.id,
          itineraryId: trip.itineraryId,
          itineraryName: trip.itineraryName,
          direction: trip.direction,
          status: live.status,
          departsAt: trip.departsAt,
          statusChangedAt: trip.statusChangedAt,
          myStopId: _membership!.stopId,
          myState: live.myState,
        ));
      }
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

  /// Declara su estado a mano (con la parada elegida y la hora de captura):
  /// se respeta hasta que el cálculo detecte un cambio real (docs/11 §11.67).
  Future<void> _report(String state, {String? stopId, List<String>? childIds, String? tripId}) async {
    await _session.api.post('/trips/${tripId ?? widget.tripId}/reports', resourceData('trip-reports', attributes: {
      'events': [
        {
          'kind': 'worker',
          'state': state,
          'stopId': ?(stopId == null ? null : int.tryParse(stopId)),
          if (childIds != null) 'childIds': [for (final id in childIds) int.tryParse(id) ?? 0],
          'manual': true,
          'capturedAt': ServerClock.stamp(DateTime.now()),
        },
      ],
    }));
    if (childIds != null) await TrackingService.setChildren(childIds);
    TrackingService.syncNow();
    await _refresh();
  }

  /// Parada del recorrido para declarar su estado (por omisión, las que siguen En espera).
  Future<LiveStop?> _pickStop(String title, {bool pending = true}) async {
    final live = _live;
    if (live == null) return null;
    var options = live.stops.where((s) => !pending || s.state == StopState.waiting).toList();
    if (options.isEmpty) options = live.stops;
    if (options.isEmpty) return null;
    if (options.length == 1) return options.first;
    return pickOne<LiveStop>(context, title, options, (s) => s.landmark, subtitle: (s) => [StopState.name(s.state), ?s.street].join(' • '));
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

  /// «Cambiar Mi estado» (docs/11 §11.67): cualquier estado, en cualquier
  /// momento; con su parada si la tiene. No viajaré solo se pone así.
  Future<void> _changeMyState() async {
    final live = _live;
    final state = await pickOne<String>(context, 'Mi estado', WorkerState.states, WorkerState.name,
        subtitle: (s) => s == live?.myState ? 'Su estado ahora' : (s == WorkerState.notTravelling ? 'Avisa que no irá' : ''));
    if (state == null || !mounted) return;
    switch (state) {
      case WorkerState.notTravelling:
        await _notTravelling();
      case WorkerState.outOfRoute:
        await _report(state);
      case WorkerState.travelling:
        final stop = await _pickStop('¿En qué parada subió?', pending: false);
        if (stop == null) return;
        final kids = await _pickChildren();
        if (kids != null) await _report(state, stopId: stop.stopId, childIds: kids);
      case WorkerState.dropped:
        final stop = await _pickStop('¿En qué parada se bajó?', pending: false);
        if (stop != null) await _report(state, stopId: stop.stopId);
      default:
        final waiting = state == WorkerState.atStop || state == WorkerState.approaching || state == WorkerState.movingAway;
        final stop = await _pickStop('¿Qué parada?', pending: waiting);
        if (stop != null) await _report(state, stopId: stop.stopId);
    }
  }

  Future<void> _notTravelling() async {
    final trip = _trip!;
    var alsoReturn = false;
    if (trip.outbound) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          icon: const Icon(Icons.block, size: 32),
          title: 'No viajaré',
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
    } else if (!await confirm(context, 'No viajaré', '¿Confirma que no irá en este viaje de regreso?', accept: 'No viajaré', icon: Icons.block, headerIcon: Icons.block, destructive: true)) {
      return;
    }
    await _report(WorkerState.notTravelling);
    if (alsoReturn) {
      final back = (await _session.api.getAll('/trips', query: {'filter[itinerary]': trip.itineraryId, 'filter[date]': apiDay(trip.date), 'filter[direction]': 'regreso'})).map(Trip.from).toList();
      for (final t in back.where((t) => t.isOpen)) {
        await _report(WorkerState.notTravelling, tripId: t.id);
      }
    }
  }

  List<ActionItem> _actions() {
    final trip = _trip;
    final live = _live;
    if (trip == null) return const [];
    final me = _session.me!;
    final manage = me.isAdmin || me.isChiefOf(trip.itineraryId);
    final mine = _travels && trip.isOpen && _locationReady == true && (live == null || live.status == TripStatus.planned || live.status == TripStatus.running);
    return [
      if (_travels && _locationReady != true) ActionItem(Icons.my_location, 'Activar ubicación', _enableLocation),
      if ((manage || live?.canManage == true) && live != null && (live.status == TripStatus.running || live.status == TripStatus.planned) && live.nextStopIndex < live.stops.length)
        ActionItem(Icons.where_to_vote, 'Marcar paso por parada', () => _markPassed(_passTarget(live))),
      // Mi estado, a mano (docs/11 §11.67): cualquier estado, en cualquier momento.
      if (mine) ActionItem(Icons.person_pin_circle_outlined, 'Cambiar Mi estado', _changeMyState),
      ActionItem(Icons.groups_outlined, 'Consultar Trabajadores', () => push(context, TripWorkersScreen(trip: trip))),
      ActionItem(Icons.description_outlined, 'Consultar Viaje', () => push(context, TripFormScreen(tripId: trip.id))),
      if (manage && trip.isPlanned && live?.status == TripStatus.planned) ActionItem(Icons.play_arrow, 'Iniciar Viaje', () => _setStatus(TripStatus.running)),
      if (manage && live?.status == TripStatus.running) ActionItem(Icons.flag_outlined, 'Terminar Viaje', () => _setStatus(TripStatus.finished)),
    ];
  }

  /// La parada que se marcaría: la próxima (en un viaje Planificado, la salida).
  LiveStop _passTarget(TripLive live) => live.status == TripStatus.planned ? live.stops.first : live.stops[live.nextStopIndex.clamp(0, live.stops.length - 1)];

  /// «Marcar paso por parada» (Jefe o Administrador, docs/11 §11.61): cuenta
  /// como la confirmación de los sensores; la parada queda Recogida.
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

  Future<void> _setStatus(String status) async {
    final (verb, doing) = tripStatusVerb(status);
    if (!await confirm(context, '$verb Viaje', '¿$verb el viaje?', accept: '$verb Viaje', icon: Icons.check)) return;
    BusyScope.relabel('$doing Viaje');
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
    final live = _live;
    // La tarjeta del viaje con su estado actual (la línea se consulta cada Z).
    final shown = Trip(
      id: trip.id,
      direction: trip.direction,
      date: trip.date,
      departureTime: trip.departureTime,
      departsAt: trip.departsAt,
      status: live?.status ?? trip.status,
      statusChangedAt: trip.statusChangedAt,
      startedAt: live?.startedAt ?? trip.startedAt,
      changes: trip.changes,
      itineraryId: trip.itineraryId,
      itineraryName: trip.itineraryName,
      vehicleTypeName: trip.vehicleTypeName,
      simulation: trip.simulation || (live?.simulation ?? false),
    );
    // Ubicación obligatoria solo para los trabajadores del viaje (docs/11 §11.62).
    final permissions = _permissions;
    if (_travels && permissions != null && !permissions.foreground) {
      return AppScaffold.list(title: title, tab: MainTab.trips, actions: _actions, children: [
        TripCard(trip: shown, departure: _departure, compact: true),
        TripPermissionsCard(permissions: permissions, onChanged: _checkLocation),
      ]);
    }
    return AppScaffold(
      title: title,
      tab: MainTab.trips,
      actions: _actions,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          TripCard(trip: shown, departure: _departure, compact: true),
          if (_travels && permissions != null && !permissions.complete && trip.isOpen) TripPermissionsCard(permissions: permissions, onChanged: _checkLocation),
          if (live == null)
            const SizedBox(height: 240, child: BusyPanel(text: 'Consultando Recorrido'))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              // Sensores pequeña (icono y cantidad) y Estado el resto del ancho, de la misma altura.
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _SensorsBox(count: live.sensors, onTap: () => _showSensors(live)),
                  const SizedBox(width: 8),
                  Expanded(child: _StateBox(lines: myStateLines(live, _travels ? _motion : null))),
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

  /// Paradas en el orden del recorrido, todas a la misma distancia, y el
  /// vehículo en su tramo (docs/11 §11.67).
  List<Widget> _line(TripLive live) {
    final stops = live.stops;
    final widgets = <Widget>[];
    final position = vehiclePosition(live);
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final number = live.outbound ? i + 1 : stops.length - i;
      final last = i == stops.length - 1;
      final when = s.passedAt == null || s.state == StopState.waiting ? null : '${i == 0 ? 'Salió' : 'Pasó'} ${formatTime(s.passedAt)}${s.passedManually ? ' (a mano)' : ''}';
      widgets.add(_LineStop(
        name: '$number. ${s.landmark}',
        state: s.state,
        when: when ?? (last ? 'Última parada' : null),
        chips: stopCountChips(s.counts, outbound: live.outbound),
        passed: s.state != StopState.waiting,
        first: i == 0,
        last: last,
        mine: s.mine,
        busOnStop: position == (i, true),
        bus: position == (i, false) ? _busText(live, s, stops[i + 1]) : null,
      ));
    }
    return widgets;
  }

  Widget _busText(TripLive live, LiveStop from, LiveStop to) {
    final stopped = live.vehicleState == 'detenido';
    final String head;
    final String detail;
    if (stopped) {
      head = 'Detenido${live.vehicleSince == null ? '' : ' desde las ${formatTime(live.vehicleSince)}'}';
      detail = live.detentionCause ?? 'En el trayecto, entre ${from.landmark} y ${to.landmark}';
    } else if (live.vehicleState == null) {
      // Sin sensores no se sabe nada del vehículo (docs/11 §11.61).
      head = 'Sin datos del vehículo';
      detail = live.sensors == 0 ? 'Ningún sensor activo todavía' : 'Esperando el primer dato de los sensores';
    } else {
      head = ['En movimiento', if (live.vehicleSpeed != null) speedText(live.vehicleSpeed!)].join(' • ');
      detail = 'Entre ${from.landmark} y ${to.landmark}';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _tx(head, color: amber, bold: true),
      _tx(detail, color: amber),
      if (live.vehicleState != null && live.sensors == 0) _tx('Último dato de las ${formatTime(live.vehicleSince)}', color: grey),
    ]);
  }
}

/// Dónde se dibuja el vehículo (docs/11 §11.67): (posición, true) sobre la
/// parada en que está detenido; (posición, false) en medio del tramo entre
/// esa parada (la última que dejó) y la siguiente; null si no se dibuja.
(int, bool)? vehiclePosition(TripLive live) {
  if (live.status != TripStatus.running || live.stops.isEmpty) return null;
  final next = live.nextStopIndex;
  if (next < live.stops.length && live.stoppedAt(next)) return (next, true);
  final left = live.lastLeftIndex >= 0 ? live.lastLeftIndex : next - 1;
  if (left < 0 || left + 1 >= live.stops.length) return null;
  return (left, false);
}

/// «4 km/h».
String speedText(double kmh) => '${kmh.round()} km/h';

/// Las 3 líneas de la tarjeta de estado (docs/11 §11.67): el estado; «[parada]
/// • [Detenido | En movimiento] • [velocidad]» (sin parada en Viajando; en
/// Dejado, donde se le dejó); «[lat, lng] • [fecha y hora]» de la última
/// ubicación. Antes de Viajando el movimiento es el suyo ([motion], calculado
/// en el teléfono); desde Viajando, el del vehículo. Código puro (se prueba).
List<String> myStateLines(TripLive live, MyMotion? motion) {
  final fresh = motion != null && motion.state != null;
  final state = fresh ? motion.state : live.myState;
  final travelling = state == WorkerState.travelling;
  final stop = travelling || state == WorkerState.notTravelling || state == WorkerState.outOfRoute
      ? null
      : (fresh ? motion.stopName : null) ?? live.myStopName ?? live.stops.where((s) => s.stopId == live.myStopId).firstOrNull?.landmark;
  final bool? moving = travelling ? (live.vehicleState == null ? null : live.vehicleState == 'en_movimiento') : motion?.moving;
  final double? speed = travelling ? live.vehicleSpeed : motion?.speedKmh;
  final second = [
    ?stop,
    if (moving != null) moving ? 'En movimiento' : 'Detenido',
    if (speed != null && moving != null) speedText(speed),
  ];
  final where = motion?.latitude == null || motion?.longitude == null
      ? 'Sin ubicación todavía'
      : '${motion!.latitude!.toStringAsFixed(5)}, ${motion.longitude!.toStringAsFixed(5)}${motion.at == null ? '' : ' • ${formatDateTime(motion.at)}'}';
  return [
    WorkerState.name(state),
    second.isEmpty ? (travelling ? 'Sin datos del vehículo' : 'Sin datos de movimiento') : second.join(' • '),
    where,
  ];
}

/// Cantidades de una parada (docs/11 §11.67), con su plural y sin ceros:
/// todas menos Viajando; en la ida sin los Dejados y en el regreso sin los
/// En Parada.
List<(String, Color)> stopCountChips(Map<String, int> counts, {required bool outbound}) => [
      for (final (state, color) in const [
        (WorkerState.approaching, grey),
        (WorkerState.movingAway, grey),
        (WorkerState.atStop, blue2),
        (WorkerState.late, purple),
        (WorkerState.leftBehind, red),
        (WorkerState.dropped, green),
      ])
        if ((counts[state] ?? 0) > 0 && WorkerState.shownInLine(state, outbound: outbound)) ('${WorkerState.count(state, counts[state]!)}: ${counts[state]}', color),
    ];

Color stopStateColor(String state) => switch (state) {
      StopState.pickedUp => green,
      StopState.flown => amber,
      StopState.skipped => red,
      _ => blue2,
    };

Widget _tx(String s, {Color? color, bool bold = false}) =>
    Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

/// Tarjeta pequeña de Sensores: el icono y la cantidad, uno al lado del otro.
class _SensorsBox extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _SensorsBox({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = readable(context, green);
    return Tooltip(
      message: count == 1 ? '1 sensor' : '$count sensores',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: green)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sensors, color: c, size: 28),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c)),
          ]),
        ),
      ),
    );
  }
}

/// Tarjeta de su estado: el icono a la izquierda y las 3 líneas a la derecha.
class _StateBox extends StatelessWidget {
  final List<String> lines;

  const _StateBox({required this.lines});

  @override
  Widget build(BuildContext context) {
    final c = readable(context, blue2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: blue2.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: blue2)),
      child: Row(children: [
        Icon(Icons.person_pin_circle_outlined, color: c, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(lines[0], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c, height: 1.2)),
            for (final l in lines.skip(1)) Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c)),
          ]),
        ),
      ]),
    );
  }
}

/// Una parada en la línea: todas con la misma altura, así las paradas quedan
/// a la misma distancia aunque físicamente no lo estén (docs/11 §11.67). La
/// línea y los iconos son los de siempre.
class _LineStop extends StatelessWidget {
  final String name;
  final String state;
  final String? when;
  final List<(String, Color)> chips;
  final bool passed;
  final bool first;
  final bool last;
  final bool mine;

  /// El vehículo, detenido sobre esta parada.
  final bool busOnStop;

  /// El vehículo en medio del tramo hacia la siguiente (con su texto).
  final Widget? bus;

  const _LineStop({
    required this.name,
    required this.state,
    this.when,
    this.chips = const [],
    this.passed = false,
    this.first = false,
    this.last = false,
    this.mine = false,
    this.busOnStop = false,
    this.bus,
  });

  /// Altura de cada parada (de un círculo al siguiente).
  static const height = 156.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const grey9 = Color(0xFF9E9E9E);
    final c = passed ? grey9 : t.colorScheme.primary;
    final busIcon = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: t.colorScheme.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: const Icon(Icons.directions_bus, size: 22, color: Colors.black),
    );
    return SizedBox(
      height: last ? 96 : height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 40,
          child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
            if (!last)
              Positioned(top: 12, bottom: -12, child: Container(width: 6, color: passed && bus == null ? grey9 : (passed ? grey9 : t.colorScheme.primary))),
            Positioned(top: 2, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: t.colorScheme.surface, shape: BoxShape.circle, border: Border.all(color: c, width: 5)))),
            if (busOnStop) Positioned(top: -6, child: busIcon),
            // En medio del tramo: a media altura entre este círculo y el siguiente.
            if (bus != null) Positioned(top: 13 + height / 2 - 19, child: busIcon),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: passed ? grey : null))),
                if (mine) ...[const SizedBox(width: 6), const Chip2('Parada habitual', green)],
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Chip2(StopState.name(state), stopStateColor(state)),
                if (when != null) ...[const SizedBox(width: 6), Flexible(child: _tx(when!))],
              ]),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [for (final (l, col) in chips) Padding(padding: const EdgeInsets.only(right: 6), child: Chip2(l, col))]),
                ),
              ],
              if (bus != null) ...[const Spacer(), Padding(padding: const EdgeInsets.only(bottom: 18), child: bus!)],
            ]),
          ),
        ),
      ]),
    );
  }
}
