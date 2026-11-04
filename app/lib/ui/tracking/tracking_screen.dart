import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/geo.dart';
import '../../services/map_tiles.dart';
import '../../services/templates.dart';
import '../../services/tracking_service.dart';
import '../../services/user_settings.dart';
import '../../services/voice.dart';
import '../theme.dart';
import '../trips/trip_context.dart';
import '../navigation.dart';
import '../qr/boarding_scan.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'boarding.dart';
import 'passengers_screen.dart';
import 'timeline.dart';

/// Recorrido en tiempo real: mapa o línea con hitos, sensores, estadísticas
/// del viaje en marcha, voz y lista de la próxima parada (para el chofer y los jefes).
class TrackingScreen extends StatefulWidget {
  final String tripId;
  final String legId;

  const TrackingScreen({super.key, required this.tripId, required this.legId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  TripContext? _context;
  TripLeg? _leg;
  /// Trazado real recorrido y recorrido de referencia del itinerario (docs/09 §19).
  List<LatLng> _path = [];
  List<LatLng> _reference = [];
  MapConfig? _mapConfig;
  DateTime? _lastPosition;
  Map<String, dynamic>? _live;
  Timer? _timer;
  late Voice _voice;
  late UserSettings _settings;
  bool _mapView = false;
  bool _sharing = false;
  bool _background = false;
  int _radius = 100;
  String? _insideStopId;
  List<Passenger>? _nextList;
  Stop? _nextStop;
  String? _error;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _settings = context.session.settings;
    _mapView = _settings.string('trip_view', 'timeline') == 'map';
    _voice = Voice(enabled: false);
    _init();
  }

  Future<void> _init() async {
    try {
      final api = context.api;
      final me = context.me;
      final data = await TripContext.load(api, widget.tripId);
      final radius = await api.get('/settings/stop_detection_radius_m');
      if (!mounted) return;
      final operate = data.canOperate(me);
      _voice.enabled = operate && _settings.boolean('tts_enabled', true);
      _radius = int.tryParse(radius.resource.string('value') ?? '') ?? 100;
      _background = await TrackingService.isRunning;
      _mapConfig = await MapTiles.config(api);
      final referenceId = data.referenceLegId(data.legs.firstWhere((leg) => leg.id == widget.legId).direction);
      if (referenceId != null && referenceId != widget.legId) {
        try {
          _reference = _points(await api.getAll('/trip-positions', query: {'filter[tripLeg]': referenceId, 'sort': 'recordedAt'}));
        } catch (_) {
          // Sin recorrido de referencia: el mapa muestra solo el trazado real.
        }
      }
      if (!mounted) return;
      setState(() {
        _context = data;
        _leg = data.legs.firstWhere((leg) => leg.id == widget.legId);
      });
      if (_leg!.isActive && DateTime.now().difference(_leg!.startedAt).inMinutes < 2) _voice.say('Comenzando viaje');
      await _poll();
      final seconds = _settings.integer('tracking_poll_foreground_seconds', 10);
      _timer = Timer.periodic(Duration(seconds: seconds), (_) => _poll());
    } catch (error) {
      setState(() => _error = 'No se pudo cargar el recorrido.');
    }
  }

  Future<void> _poll() async {
    final data = _context;
    if (data == null || !mounted) return;
    try {
      final api = context.api;
      final previous = _leg!;
      final leg = TripLeg.from((await api.get('/trip-legs/${widget.legId}')).resource);
      final query = {'filter[tripLeg]': widget.legId, 'sort': 'recordedAt', if (_lastPosition != null) 'filter[since]': _lastPosition!.toUtc().toIso8601String()};
      final positions = await api.getAll('/trip-positions', query: query);
      if (positions.isNotEmpty) {
        _lastPosition = positions.last.date('recordedAt');
        _path = [..._path, ..._points(positions)];
      }
      if (_ticks++ % 3 == 0) {
        final live = await api.get('/statistics/live-trip', query: {'filter[trip]': widget.tripId});
        final rows = (live.resource.attributes['rows'] as List).cast<Map>();
        _live = rows.cast<Map<String, dynamic>>().firstWhere((row) => row['direction'] == leg.direction, orElse: () => {});
      }
      await _events(previous, leg, data);
      if (mounted) setState(() => _leg = leg);
    } catch (_) {
      // Sin conexión: se mantiene lo último que se tenía.
    }
  }

  static double? _number(Object? value) => value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

  /// Posiciones registradas (trip-positions) como puntos del trazado.
  static List<LatLng> _points(List<Resource> positions) => [
        for (final position in positions)
          if (_number(position.attributes['latitude']) != null && _number(position.attributes['longitude']) != null)
            LatLng(_number(position.attributes['latitude'])!, _number(position.attributes['longitude'])!),
      ];

  /// Eventos del recorrido (7.19): llegada, salida de una parada y fin.
  Future<void> _events(TripLeg previous, TripLeg leg, TripContext data) async {
    final stops = data.orderedStops(leg.direction);
    final known = previous.stopPasses.map((p) => p.stopId).toSet();

    for (final pass in leg.stopPasses.where((p) => !known.contains(p.stopId))) {
      final stop = data.stop(pass.stopId);
      if (stop != null) {
        await _voice.say('Llegando a parada ${stop.landmark}');
        _insideStopId = stop.id;
      }
    }

    if (_insideStopId != null && leg.latitude != null) {
      final inside = data.stop(_insideStopId);
      if (inside != null && distanceMeters(inside.latitude, inside.longitude, leg.latitude!, leg.longitude!) > _radius) {
        final index = stops.indexWhere((s) => s.id == inside.id);
        final next = index >= 0 && index + 1 < stops.length ? stops[index + 1] : null;
        _insideStopId = null;
        if (next != null) {
          await _voice.say('Saliendo de parada ${inside.landmark}, próxima parada ${next.landmark}');
          await _loadNextList(next, leg.direction);
        }
      }
    }

    if (previous.isActive && !leg.isActive) {
      await _voice.say('Terminando viaje');
    }
  }

  Future<void> _loadNextList(Stop stop, String direction) async {
    if (!_context!.canOperate(context.me)) return;
    final document = await context.api.get('/trips/${widget.tripId}/passengers', query: {'filter[stop]': stop.id, 'filter[direction]': direction});
    if (!mounted) return;
    setState(() {
      _nextStop = stop;
      _nextList = document.resources.map(Passenger.from).toList();
    });
  }

  Future<void> _toggleSharing(bool share) async {
    if (share) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showMessage(context, 'Hace falta permiso de ubicación para compartirla.');
        return;
      }
    }
    setState(() => _sharing = share);
    await _restartBackground();
  }

  Future<void> _toggleBackground(bool value) async {
    setState(() => _background = value);
    await _restartBackground();
  }

  Future<void> _restartBackground() async {
    final data = _context!;
    final me = context.me;
    if (!_sharing && !_background) {
      await TrackingService.stop();
      return;
    }
    await TrackingService.start(
      leg: _leg!,
      trip: data.trip,
      orderedStops: data.stops,
      myStopId: me.stopIdIn(data.trip.itineraryId),
      share: _sharing,
      iAmDriver: data.isDriver(me),
      settings: _settings,
    );
  }

  Future<void> _end() async {
    if (!await confirm(context, 'Finalizar recorrido', '¿Terminó el ${_leg!.directionLabel.toLowerCase()}?')) return;
    if (!mounted) return;
    final ok = await runAction(context, () => context.api.patch('/trip-legs/${widget.legId}', {
          'data': {'type': 'trip-legs', 'id': widget.legId, 'attributes': {'endedAt': DateTime.now().toUtc().toIso8601String()}},
        }));
    if (ok) {
      await _voice.say('Terminando viaje');
      await _poll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _context;
    final leg = _leg;
    if (data == null || leg == null) {
      return AppScaffold(title: 'Recorrido', tab: MainTab.trips, body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    }
    final me = context.me;
    final operate = data.canOperate(me);
    final stops = data.orderedStops(leg.direction);
    final canShare = me.isMemberOf(data.trip.itineraryId) || data.isDriver(me);

    return AppScaffold(
        title: '${leg.directionLabel} · ${data.trip.itineraryName ?? ''}',
        tab: MainTab.trips,
        appBarActions: [
          IconButton(
            tooltip: _mapView ? 'Ver línea con hitos' : 'Ver mapa',
            icon: Icon(_mapView ? Icons.timeline : Icons.map_outlined),
            onPressed: () => setState(() => _mapView = !_mapView),
          ),
          if (operate)
            IconButton(
              tooltip: _voice.enabled ? 'Silenciar voz' : 'Activar voz',
              icon: Icon(_voice.enabled ? Icons.volume_up : Icons.volume_off),
              onPressed: () => setState(() => _voice.enabled = !_voice.enabled),
            ),
        ],
      body: Column(children: [
        _StatusBar(leg: leg, live: _live),
        if (leg.deviating)
          Container(
            width: double.infinity,
            color: overloadColor,
            padding: const EdgeInsets.all(8),
            child: const Row(children: [
              Icon(Icons.alt_route, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('El transporte se ha desviado del recorrido de referencia.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ]),
          ),
        Expanded(
          child: _mapView ? _map(stops, leg) : ProportionalTimeline(stops: stops, leg: leg, highlightStopId: me.stopIdIn(data.trip.itineraryId)),
        ),
        if (_nextList != null && operate) _NextStopPanel(stop: _nextStop!, passengers: _nextList!, direction: leg.direction, onClose: () => setState(() => _nextList = null)),
        if (leg.isActive)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(children: [
                if (canShare)
                  SwitchListTile(
                    dense: true,
                    title: const Text('Compartir mi ubicación (sensor)'),
                    value: _sharing,
                    onChanged: _toggleSharing,
                  ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Seguir con la aplicación cerrada'),
                  subtitle: const Text('Avisos de paso por paradas'),
                  value: _background,
                  onChanged: _toggleBackground,
                ),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  if (data.isPassenger(me)) BusyButton.tonal(onPressed: () => selfBoarding(context, leg), icon: const Icon(Icons.how_to_reg), child: const Text('Ya subí')),
                  if (data.isPassenger(me))
                    OutlinedButton.icon(
                      onPressed: () => AppRoutes.myQr(context),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Mi QR'),
                    ),
                  if (data.isDriver(me) || data.can(me, Op.trackingScanBoarding))
                    BusyButton(onPressed: () => scanBoardings(context, data, leg), icon: const Icon(Icons.qr_code_scanner), child: const Text('Escanear QR')),
                  if (operate)
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengersScreen(context: data, direction: leg.direction, leg: leg))),
                      icon: const Icon(Icons.groups),
                      label: const Text('Pasajeros'),
                    ),
                  if (operate) BusyButton.outlined(onPressed: _end, icon: const Icon(Icons.stop_circle_outlined), child: const Text('Finalizar viaje')),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _map(List<Stop> stops, TripLeg leg) {
    final config = _mapConfig;
    if (config == null) return const Center(child: CircularProgressIndicator());
    final api = context.api;
    final colors = Theme.of(context).colorScheme;
    final points = stops.map((s) => LatLng(s.latitude, s.longitude)).toList();
    final passes = {for (final pass in leg.stopPasses) pass.stopId: pass};
    final vehicle = leg.latitude == null ? null : LatLng(leg.latitude!, leg.longitude!);
    final fit = [...points, ..._path];
    return FlutterMap(
      options: MapOptions(
        initialCenter: vehicle ?? (points.isEmpty ? LatLng(config.bounds.south, config.bounds.west) : points.first),
        initialZoom: 13,
        minZoom: config.minZoom.toDouble(),
        maxZoom: config.maxZoom.toDouble(),
        cameraConstraint: MapTiles.constraint(config),
        initialCameraFit: fit.length > 1 ? CameraFit.coordinates(coordinates: fit, padding: const EdgeInsets.all(40)) : null,
      ),
      children: [
        MapTiles.layer(api, config),
        // Sin líneas rectas entre paradas: solo el recorrido de referencia y el trazado real.
        PolylineLayer(polylines: [
          if (_reference.length > 1) Polyline(points: _reference, strokeWidth: 6, color: Colors.grey.withValues(alpha: 0.7)),
          if (_path.length > 1) Polyline(points: _path, strokeWidth: 4, color: colors.primary),
        ]),
        MarkerLayer(markers: [
          for (final stop in stops)
            Marker(
              point: LatLng(stop.latitude, stop.longitude),
              width: 36,
              height: 36,
              child: Tooltip(
                message: stop.landmark,
                child: Icon(Icons.location_on, size: 36, color: _stopColor(passes[stop.id], colors)),
              ),
            ),
          for (final incident in leg.incidents.where((i) => i.latitude != null && i.longitude != null))
            Marker(
              point: LatLng(incident.latitude!, incident.longitude!),
              width: 30,
              height: 30,
              child: Tooltip(
                message: '${incident.label} · ${formatTime(incident.startedAt)}',
                child: CircleAvatar(
                  backgroundColor: incident.type == 'not_stopped' ? saturatedColor : overloadColor,
                  child: Icon(
                    const {'not_stopped': Icons.fast_forward, 'skipped': Icons.block, 'deviation': Icons.alt_route}[incident.type] ?? Icons.warning_amber,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (vehicle != null)
            Marker(
              point: vehicle,
              width: 40,
              height: 40,
              child: CircleAvatar(backgroundColor: colors.primary, child: const Icon(Icons.directions_bus, color: Colors.white)),
            ),
        ]),
      ],
    );
  }

  static Color _stopColor(StopPass? pass, ColorScheme colors) {
    if (pass == null) return Colors.grey;
    if (pass.skipped) return overloadColor;
    if (pass.notStopped) return saturatedColor;
    return colors.primary;
  }
}

class _StatusBar extends StatelessWidget {
  final TripLeg leg;
  final Map<String, dynamic>? live;

  const _StatusBar({required this.leg, this.live});

  static int _int(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (Icons.sensors, plural(leg.activeSensors, 'sensor', 'sensores')),
      if (leg.positionAt != null) (Icons.schedule, 'Actualizado ${formatTime(leg.positionAt!)}'),
      if (live != null && live!.isNotEmpty) ...[
        (Icons.people, '${live!['boarded']} a bordo / ${live!['capacity']}'),
        if (_int(live!['children']) > 0) (Icons.child_care, plural(_int(live!['children']), 'niño', 'niños')),
        (Icons.flag, '${plural(_int(live!['stopsPassed']), 'pasada', 'pasadas')} · ${plural(_int(live!['stopsRemaining']), 'restante', 'restantes')}'),
        (Icons.route, '${live!['traveledKm']} km · faltan ${live!['remainingKm']} km'),
        if (_int(live!['startDelayMinutes']) > 0) (Icons.timer_outlined, 'Comenzó con ${live!['startDelayMinutes']} min de atraso'),
      ],
      if (leg.notStoppedCount > 0) (Icons.fast_forward, 'No se detuvo en ${leg.notStoppedCount}'),
      if (leg.skippedCount > 0) (Icons.block, 'Saltadas ${leg.skippedCount}'),
      if (!leg.isActive) (Icons.flag_circle, 'Recorrido terminado'),
    ];
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(8),
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        for (final item in items)
          Row(mainAxisSize: MainAxisSize.min, children: [Icon(item.$1, size: 16), const SizedBox(width: 4), Text(item.$2, style: Theme.of(context).textTheme.bodySmall)]),
      ]),
    );
  }
}

/// Lista de la próxima parada: quiénes suben (regreso) o se bajan (salida).
class _NextStopPanel extends StatelessWidget {
  final Stop stop;
  final List<Passenger> passengers;
  final String direction;
  final VoidCallback onClose;

  const _NextStopPanel({required this.stop, required this.passengers, required this.direction, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            dense: true,
            title: Text('Próxima parada: ${stop.landmark}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(direction == 'return'
                ? plural(passengers.length, 'trabajador sube', 'trabajadores suben')
                : plural(passengers.length, 'trabajador se baja', 'trabajadores se bajan')),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in passengers)
                ListTile(
                  dense: true,
                  leading: WorkerAvatar(p.worker, radius: 16),
                  title: Text(p.worker.fullName),
                  subtitle: Wrap(spacing: 8, children: [
                    if ((p.eligibleChildren ?? 0) > 0) Text('${plural(p.eligibleChildren!, 'hijo', 'hijos')} con derecho'),
                  ]),
                  trailing: p.boarded ? const Icon(Icons.check_circle, color: Colors.green) : null,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
