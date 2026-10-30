import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Pregunta con cuántos niños sube (0 si no tiene hijos con derecho).
Future<int?> askChildren(BuildContext context, int maximum, {int? initial}) async {
  if (maximum <= 0) return 0;
  var value = initial ?? maximum;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('¿Con cuántos niños sube?'),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: value > 0 ? () => setState(() => value--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$value', style: Theme.of(context).textTheme.headlineMedium),
          IconButton(onPressed: value < maximum ? () => setState(() => value++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, value), child: const Text('Aceptar')),
        ],
      ),
    ),
  );
}

/// "Ya subí".
Future<void> selfBoarding(BuildContext context, TripLeg leg, int children) async {
  final count = await askChildren(context, children);
  if (count == null || !context.mounted) return;
  await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {
        'method': 'self',
        'childrenCount': count,
      }, relationships: {'tripLeg': ResourceId('trip-legs', leg.id)})), success: 'Subida registrada');
}

/// Código QR del trabajador para que el chofer o un jefe registre su subida.
/// Se renueva antes de caducar.
class BoardingPassScreen extends StatefulWidget {
  final TripLeg leg;

  const BoardingPassScreen({super.key, required this.leg});

  @override
  State<BoardingPassScreen> createState() => _BoardingPassScreenState();
}

class _BoardingPassScreenState extends State<BoardingPassScreen> {
  String? _token;
  DateTime? _expires;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final resource = (await context.api.post('/boarding-passes', resourceData('boarding-passes', relationships: {
        'tripLeg': ResourceId('trip-legs', widget.leg.id),
      }))).resource;
      final expires = resource.date('expiresAt')!;
      setState(() {
        _token = resource.string('token');
        _expires = expires;
        _error = null;
      });
      _timer?.cancel();
      final wait = expires.difference(DateTime.now()) - const Duration(seconds: 10);
      _timer = Timer(wait.isNegative ? const Duration(seconds: 5) : wait, _refresh);
    } catch (error) {
      setState(() => _error = 'No se pudo generar el código. Revisa tu conexión.');
      _timer = Timer(const Duration(seconds: 10), _refresh);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi código QR')),
      body: Center(
        child: _token == null
            ? (_error == null ? const CircularProgressIndicator() : Text(_error!))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(data: _token!, size: 280),
                ),
                const SizedBox(height: 16),
                Text(context.me.fullName, style: Theme.of(context).textTheme.titleLarge),
                Text('Muéstralo al chofer o al Jefe de itinerario'),
                if (_expires != null) Text('Se renueva automáticamente (válido hasta ${formatTime(_expires!)})', style: Theme.of(context).textTheme.bodySmall),
              ]),
      ),
    );
  }
}
