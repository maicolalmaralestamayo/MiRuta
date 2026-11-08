import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/shared_location.dart';
import '../../services/tracking/worker_tracker.dart';
import '../management/forms.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Ubicación compartida desde WhatsApp, Telegram, Google Maps, OsmAnd… (docs/11
/// §11.51): «Crear parada nueva» o «Cambiar la ubicación de una parada
/// existente». Solo el Administrador y el Jefe de itinerario.
class SharedLocationScreen extends StatefulWidget {
  final String text;

  const SharedLocationScreen({super.key, required this.text});

  @override
  State<SharedLocationScreen> createState() => _SharedLocationScreenState();
}

class _SharedLocationScreenState extends State<SharedLocationScreen> {
  GeoPoint? _point;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final point = await SharedLocation.resolve(widget.text);
      if (!mounted) return;
      setState(() {
        _point = point;
        _loading = false;
        if (point == null) _error = 'No se encontró una ubicación en lo compartido. Si es un enlace corto, hace falta conexión a Internet.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo abrir el enlace: compruebe la conexión a Internet.';
        });
      }
    }
  }

  Future<void> _create() async {
    final me = context.read<Session>().me!;
    await push(context, StopForm(itineraryId: me.isAdmin ? null : me.chiefItineraryId, latitude: _point!.latitude, longitude: _point!.longitude));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _change() async {
    final me = context.read<Session>().me!;
    final api = context.read<Session>().api;
    final stops = (await api.getAll('/stops', query: {if (!me.isAdmin) 'filter[itinerary]': me.chiefItineraryId})).map(Stop.from).toList();
    if (!mounted) return;
    final stop = await pickOne<Stop>(context, 'Parada', stops, (s) => s.landmark, subtitle: (s) => s.address, search: true);
    if (stop == null || !mounted) return;
    if (!await confirm(context, 'Cambiar la ubicación', '¿Poner a ${stop.landmark} la ubicación compartida (${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)})?',
        accept: 'Cambiar', icon: Icons.edit_location_alt_outlined)) {
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () => api.patch('/stops/${stop.id}', resourceData('stops', id: stop.id, attributes: {
          'latitude': double.parse(_point!.latitude.toStringAsFixed(6)),
          'longitude': double.parse(_point!.longitude.toStringAsFixed(6)),
        })), success: 'Ubicación de ${stop.landmark} cambiada.');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final point = _point;
    return AppScaffold.list(
      title: 'Ubicación compartida',
      tab: MainTab.management,
      children: [
        if (_loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (_error != null) NoticeCard(icon: Icons.location_off, title: 'Sin ubicación', detail: _error!, color: red),
        if (point != null) ...[
          InfoCard(
            images: const [CardImage(icon: Icons.place)],
            title: 'Ubicación recibida',
            lines: ['Latitud ${point.latitude.toStringAsFixed(5)}', 'Longitud ${point.longitude.toStringAsFixed(5)}'],
          ),
          if (!me.manages)
            const NoticeCard(
              icon: Icons.lock_outline,
              title: 'Sin permiso',
              detail: 'Solo el Administrador y el Jefe de itinerario crean paradas o cambian su ubicación.',
              color: red,
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(height: 52, child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Crear parada nueva'))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => runAction(context, _change),
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Cambiar la ubicación de una parada existente'),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
