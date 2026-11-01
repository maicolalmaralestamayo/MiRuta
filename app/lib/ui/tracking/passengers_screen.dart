import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../trips/trip_context.dart';
import '../widgets/common.dart';
import 'boarding.dart';

/// Trabajadores por parada (en el orden del trayecto) y, dentro de cada una,
/// alfabéticamente; con el registro de subida manual o por QR.
class PassengersScreen extends StatefulWidget {
  final TripContext context;
  final String direction;
  final TripLeg? leg;

  const PassengersScreen({super.key, required this.context, this.direction = 'return', this.leg});

  @override
  State<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends State<PassengersScreen> {
  late String _direction = widget.direction;
  // Una vista por sentido: al cambiar de sentido se cargan sus trabajadores.
  final _views = {'outbound': GlobalKey<AsyncViewState<List<Passenger>>>(), 'return': GlobalKey<AsyncViewState<List<Passenger>>>()};

  TripLeg? get _leg => widget.leg?.direction == _direction ? widget.leg : widget.context.leg(_direction);

  Future<List<Passenger>> _load() async {
    final document = await context.api.get('/trips/${widget.context.trip.id}/passengers', query: {'filter[direction]': _direction});
    return document.resources.map(Passenger.from).toList();
  }

  Future<void> _board(Passenger passenger) async {
    final leg = _leg;
    if (leg == null || !leg.isActive) {
      showMessage(context, 'El ${TripLeg.directionName(_direction).toLowerCase()} no está en curso.');
      return;
    }
    final count = await askChildren(context, passenger.eligibleChildren, initial: passenger.boardedChildren);
    if (count == null || !mounted) return;
    await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {'method': 'manual', 'childrenCount': count}, relationships: {
          'tripLeg': ResourceId('trip-legs', leg.id),
          'worker': ResourceId('workers', passenger.worker.id),
        })));
    _views[_direction]!.currentState?.reload();
  }

  Future<void> _scan() async {
    final leg = _leg;
    if (leg == null || !leg.isActive) {
      showMessage(context, 'El ${TripLeg.directionName(_direction).toLowerCase()} no está en curso.');
      return;
    }
    final token = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerScreen()));
    if (token == null || !mounted) return;
    await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {'method': 'qr', 'boardingPassToken': token}, relationships: {
          'tripLeg': ResourceId('trip-legs', leg.id),
        })), success: 'Subida registrada');
    _views[_direction]!.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.context.orderedStops(_direction);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trabajadores'),
        actions: [IconButton(tooltip: 'Escanear QR', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'outbound', icon: Icon(Icons.north_east), label: Text('Viaje de ida')),
              ButtonSegment(value: 'return', icon: Icon(Icons.south_west), label: Text('Viaje de regreso')),
            ],
            selected: {_direction},
            onSelectionChanged: (value) => setState(() => _direction = value.first),
          ),
        ),
        Expanded(
          child: AsyncView<List<Passenger>>(
            key: _views[_direction],
            load: _load,
            builder: (context, passengers, reload) {
              final boarded = passengers.where((p) => p.boarded).length;
              final children = passengers.fold<int>(0, (sum, p) => sum + p.eligibleChildren);
              return ListView(children: [
                ListTile(
                  title: Text('$boarded de ${plural(passengers.length, 'trabajador registrado', 'trabajadores registrados')}'),
                  subtitle: children > 0 ? Text(plural(children, 'niño', 'niños')) : null,
                ),
                for (final stop in stops) ...[
                  if (passengers.any((p) => p.stopId == stop.id)) SectionTitle(stop.landmark),
                  for (final p in passengers.where((p) => p.stopId == stop.id))
                    BusyListTile(
                      leading: WorkerAvatar(p.worker),
                      title: Text(p.worker.fullName),
                      subtitle: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (p.worker.rank != null) RankBadge(p.worker.rank),
                        if (p.eligibleChildren > 0) Text(plural(p.eligibleChildren, 'niño', 'niños')),
                        if (p.boarded)
                          Text('Subió (${_method(p.boardingMethod)}'
                              '${p.boardedChildren != null && p.boardedChildren! > 0 ? ', ${plural(p.boardedChildren!, 'niño', 'niños')}' : ''})'),
                      ]),
                      trailing: p.boarded ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.radio_button_unchecked),
                      onTap: () => _board(p),
                    ),
                ],
              ]);
            },
          ),
        ),
      ]),
    );
  }

  String _method(String? method) => const {'automatic': 'automática', 'self': 'Ya subí', 'qr': 'QR', 'manual': 'manual'}[method] ?? '';
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código QR')),
      body: MobileScanner(
        onDetect: (capture) {
          final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
          if (value != null && !_done) {
            _done = true;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
