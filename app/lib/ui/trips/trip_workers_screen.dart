import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

/// «Trabajadores» del viaje (docs/11 §11.33): los esperados y quienes
/// informaron su estado, por parada en el orden del recorrido.
class TripWorkersScreen extends StatelessWidget {
  final Trip trip;

  const TripWorkersScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Trabajadores',
      subtitle: '${trip.itineraryName ?? ''} • ${trip.directionName} • ${formatDate(trip.date)}',
      tab: MainTab.trips,
      body: DataView<(List<TripWorker>, List<Stop>)>(
        kinds: const {'trips'},
        load: () async {
          final api = context.read<Session>().api;
          final workers = await TripWorker.load(api, trip.id);
          final stops = (await api.getAll('/stops', query: {'filter[itinerary]': trip.itineraryId, 'sort': 'position'})).map(Stop.from).toList();
          return (workers, stops);
        },
        builder: (context, data, reload) {
          final ordered = trip.outbound ? data.$2 : data.$2.reversed.toList();
          final byStop = <String?, List<TripWorker>>{};
          for (final w in data.$1) {
            byStop.putIfAbsent(w.stopId, () => []).add(w);
          }
          Widget card(TripWorker w) => InfoCard(
                images: [CardImage(url: w.photoUrl, icon: Icons.person, round: true)],
                title: w.name,
                lines: [
                  WorkerState.name(w.state),
                  if (w.children > 0) plural(w.children, 'niño', 'niños'),
                  if (!w.expected) 'No esperado',
                  if (trip.isRunning) w.sensorText(trip.outbound),
                ],
                chip: w.isChief ? const Chip2('Jefe', green) : null,
              );
          return ListView(padding: const EdgeInsets.only(bottom: 32), physics: const AlwaysScrollableScrollPhysics(), children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('${plural(data.$1.length, 'trabajador', 'trabajadores')} en total')),
            for (final s in ordered)
              if (byStop[s.id] != null)
                FoldSection<TripWorker>(storageKey: 'viaje.trabajadores.${s.id}', title: '${s.positionIn(trip.itineraryId) ?? ''}. ${s.landmark}', items: byStop[s.id]!, builder: card),
            if (byStop[null] != null) FoldSection<TripWorker>(storageKey: 'viaje.trabajadores.sin', title: 'Sin parada', items: byStop[null]!, builder: card),
          ]);
        },
      ),
    );
  }
}

/// Un trabajador del viaje (GET trips/{id}/passengers), con por qué es o no
/// sensor (docs/11 §11.61).
class TripWorker {
  final String name;
  final String? photoUrl;
  final bool expected;
  final String? state;
  final int children;
  final bool isChief;
  final String? stopId;
  final DateTime? lastSeenAt;
  final bool sensor;

  /// sensor, no_en_vehiculo, sin_gps o sin_enviar.
  final String sensorReason;

  const TripWorker(this.name, this.photoUrl, this.expected, this.state, this.children, this.isChief, this.stopId,
      {this.lastSeenAt, this.sensor = false, this.sensorReason = 'sin_enviar'});

  factory TripWorker.from(Resource r) => TripWorker(
        r.string('fullName') ?? '',
        r.string('photoUrl'),
        r.attributes['expected'] != false,
        r.string('state'),
        r.integer('childrenCount') ?? 0,
        r.boolean('isChief'),
        r.relId('stop')?.id,
        lastSeenAt: r.date('lastSeenAt')?.toLocal(),
        sensor: r.boolean('sensor'),
        sensorReason: r.string('sensorReason') ?? 'sin_enviar',
      );

  static Future<List<TripWorker>> load(ApiClient api, String tripId) async =>
      [for (final r in (await api.get('/trips/$tripId/passengers')).resources) TripWorker.from(r)];

  /// «No está Viajando (está Botado)», «Sin enviar desde las 18:41 • ¿app cerrada o sin conexión?», «Sin GPS»…
  String sensorText(bool outbound) {
    final since = lastSeenAt == null ? '' : ' desde las ${formatTime(lastSeenAt)}';
    switch (sensorReason) {
      case 'sensor':
        return 'Sensor activo: envía con GPS';
      case 'no_en_vehiculo':
        return 'No está ${outbound ? 'Viajando' : 'Recogido'} (está ${state == null ? 'sin estado' : WorkerState.name(state)})';
      case 'sin_gps':
        return 'Sin GPS: su teléfono envía sin ubicación$since';
      default:
        return lastSeenAt == null ? 'Su teléfono no ha enviado nada • ¿app cerrada o sin permiso?' : 'Sin enviar$since • ¿app cerrada o sin conexión?';
    }
  }
}
