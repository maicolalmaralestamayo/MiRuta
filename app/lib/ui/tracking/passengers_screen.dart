import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../trips/trip_context.dart';
import '../widgets/common.dart';
import 'boarding.dart';

/// Pasajeros por parada (en el orden del trayecto) y, dentro de cada una,
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
  final _view = GlobalKey<AsyncViewState<List<Passenger>>>();

  TripLeg? get _leg => widget.leg?.direction == _direction ? widget.leg : widget.context.leg(_direction);

  Future<List<Passenger>> _load() async {
    final document = await context.api.get('/trips/${widget.context.trip.id}/passengers', query: {'filter[direction]': _direction});
    return document.resources.map(Passenger.from).toList();
  }

  Future<void> _board(Passenger passenger) async {
    final leg = _leg;
    if (leg == null || !leg.isActive) {
      showMessage(context, 'El ${_direction == 'return' ? 'regreso' : 'salida'} no está en curso.');
      return;
    }
    final count = await askChildren(context, passenger.eligibleChildren, initial: passenger.boardedChildren);
    if (count == null || !mounted) return;
    await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {'method': 'manual', 'childrenCount': count}, relationships: {
          'tripLeg': ResourceId('trip-legs', leg.id),
          'worker': ResourceId('workers', passenger.worker.id),
        })));
    _view.currentState?.reload();
  }

  Future<void> _scan() async {
    final leg = _leg;
    if (leg == null || !leg.isActive) {
      showMessage(context, 'El trayecto no está en curso.');
      return;
    }
    final token = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerScreen()));
    if (token == null || !mounted) return;
    await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {'method': 'qr', 'boardingPassToken': token}, relationships: {
          'tripLeg': ResourceId('trip-legs', leg.id),
        })), success: 'Subida registrada');
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.context.orderedStops(_direction);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pasajeros'),
        actions: [IconButton(tooltip: 'Escanear QR', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'outbound', label: Text('Salida')), ButtonSegment(value: 'return', label: Text('Regreso'))],
            selected: {_direction},
            onSelectionChanged: (value) => setState(() => _direction = value.first),
          ),
        ),
        Expanded(
          child: AsyncView<List<Passenger>>(
            key: _view,
            load: _load,
            builder: (context, passengers, reload) {
              final boarded = passengers.where((p) => p.boarded).length;
              return ListView(children: [
                ListTile(
                  title: Text('$boarded de ${passengers.length} registrados'),
                  subtitle: Text('${passengers.fold<int>(0, (sum, p) => sum + p.eligibleChildren)} niño(s) con derecho a viajar (van cargados)'),
                ),
                for (final stop in stops) ...[
                  if (passengers.any((p) => p.stopId == stop.id)) SectionTitle(stop.landmark),
                  for (final p in passengers.where((p) => p.stopId == stop.id))
                    BusyListTile(
                      leading: CircleAvatar(child: Text('${p.position}')),
                      title: Text(p.worker.fullName),
                      subtitle: Text([
                        if (p.worker.rank != null) p.worker.rank!.name,
                        if (p.eligibleChildren > 0) '${p.eligibleChildren} niño(s) con derecho',
                        if (p.boarded) 'Subió (${_method(p.boardingMethod)}${p.boardedChildren != null && p.boardedChildren! > 0 ? ', ${p.boardedChildren} niño(s)' : ''})',
                      ].join(' · ')),
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
