import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
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
          final document = await api.get('/trips/${trip.id}/passengers');
          final stops = (await api.getAll('/stops', query: {'filter[itinerary]': trip.itineraryId, 'sort': 'position'})).map(Stop.from).toList();
          return ([for (final r in document.resources) TripWorker(r.string('fullName') ?? '', r.string('photoUrl'), r.attributes['expected'] != false, r.string('state'), r.integer('childrenCount') ?? 0, r.boolean('isChief'), r.relId('stop')?.id)], stops);
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

/// Un trabajador del viaje.
class TripWorker {
  final String name;
  final String? photoUrl;
  final bool expected;
  final String? state;
  final int children;
  final bool isChief;
  final String? stopId;

  const TripWorker(this.name, this.photoUrl, this.expected, this.state, this.children, this.isChief, this.stopId);
}
