import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/geo.dart';
import '../../services/templates.dart';
import '../../services/tracking_service.dart';
import '../../services/user_settings.dart';
import '../../services/voice.dart';
import '../trips/trip_context.dart';
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
  List<LatLng> _path = [];
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
        // El trazado se dibuja con la posición combinada (no con cada sensor).
        if (leg.latitude != null) _path = [..._path, LatLng(leg.latitude!, leg.longitude!)];
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
      myStopId: me.stopId,
      share: _sharing,
      iAmDriver: me.roles.driverId == data.trip.driverId,
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
      return Scaffold(appBar: AppBar(title: const Text('Recorrido')), body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    }
    final me = context.me;
    final operate = data.canOperate(me);
    final stops = data.orderedStops(leg.direction);
    final canShare = me.itineraryId == data.trip.itineraryId || me.roles.driverId == data.trip.driverId;

    return Scaffold(
      appBar: AppBar(
        title: Text('${leg.directionLabel} · ${data.trip.itineraryName ?? ''}'),
        actions: [
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
      ),
      body: Column(children: [
        _StatusBar(leg: leg, live: _live),
        Expanded(
          child: _mapView ? _map(stops, leg) : ProportionalTimeline(stops: stops, leg: leg, highlightStopId: me.stopId),
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
                  title: const Text('Seguir con la app cerrada'),
                  subtitle: const Text('Avisos de paso por paradas'),
                  value: _background,
                  onChanged: _toggleBackground,
                ),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  if (data.isPassenger(me)) FilledButton.tonalIcon(onPressed: () => selfBoarding(context, leg, me.childrenCount), icon: const Icon(Icons.how_to_reg), label: const Text('Ya subí')),
                  if (data.isPassenger(me))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BoardingPassScreen(leg: leg))),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Mi QR'),
                    ),
                  if (operate)
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengersScreen(context: data, direction: leg.direction, leg: leg))),
                      icon: const Icon(Icons.format_list_numbered),
                      label: const Text('Pasajeros'),
                    ),
                  if (operate) OutlinedButton.icon(onPressed: _end, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Finalizar')),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _map(List<Stop> stops, TripLeg leg) {
    final points = stops.map((s) => LatLng(s.latitude, s.longitude)).toList();
    final passed = leg.stopPasses.map((p) => p.stopId).toSet();
    final vehicle = leg.latitude == null ? null : LatLng(leg.latitude!, leg.longitude!);
    return FlutterMap(
      options: MapOptions(
        initialCenter: vehicle ?? (points.isEmpty ? const LatLng(0, 0) : points.first),
        initialZoom: 13,
        initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40)) : null,
      ),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.mitransporte.mitransporte'),
        PolylineLayer(polylines: [
          Polyline(points: points, strokeWidth: 3, color: Colors.grey),
          if (_path.length > 1) Polyline(points: _path, strokeWidth: 5, color: Theme.of(context).colorScheme.primary),
        ]),
        MarkerLayer(markers: [
          for (final stop in stops)
            Marker(
              point: LatLng(stop.latitude, stop.longitude),
              width: 36,
              height: 36,
              child: Tooltip(
                message: stop.landmark,
                child: Icon(Icons.location_on, size: 36, color: passed.contains(stop.id) ? Theme.of(context).colorScheme.primary : Colors.grey),
              ),
            ),
          if (vehicle != null)
            Marker(
              point: vehicle,
              width: 40,
              height: 40,
              child: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(Icons.directions_bus, color: Colors.white)),
            ),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  final TripLeg leg;
  final Map<String, dynamic>? live;

  const _StatusBar({required this.leg, this.live});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (Icons.sensors, '${leg.activeSensors} sensor(es)'),
      if (leg.positionAt != null) (Icons.schedule, 'Actualizado ${formatTime(leg.positionAt!)}'),
      if (live != null && live!.isNotEmpty) ...[
        (Icons.people, '${live!['boarded']} a bordo / ${live!['capacity']}'),
        (Icons.child_care, '${live!['children']} niños'),
        (Icons.flag, '${live!['stopsPassed']} pasadas · ${live!['stopsRemaining']} restantes'),
        (Icons.route, '${live!['traveledKm']} km · faltan ${live!['remainingKm']} km'),
        (Icons.timer_outlined, 'Retraso al iniciar: ${live!['startDelayMinutes']} min'),
      ],
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
            subtitle: Text(direction == 'return' ? '${passengers.length} suben, en orden de subida' : '${passengers.length} se bajan'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in passengers)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${p.order}', style: const TextStyle(fontSize: 12))),
                  title: Text(p.worker.fullName),
                  subtitle: Text([if (p.worker.rank != null) p.worker.rank!.name, if (p.eligibleChildren > 0) '${p.eligibleChildren} niño(s)'].join(' · ')),
                  trailing: p.boarded ? const Icon(Icons.check_circle, color: Colors.green) : null,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
