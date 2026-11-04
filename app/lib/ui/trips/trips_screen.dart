import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';
import 'trip_card.dart';
import 'trip_context.dart';

/// Viajes (pestaña Viajes y botón de Inicio; docs/11 §11.18, maqueta
/// pantallas-final.png, 7). Con selector de Entidad: «En curso» y
/// «Confirmados» de la Entidad elegida (los que puede ver: los de su
/// itinerario, los que conduce y, según sus roles, los demás). Sin botón
/// Acciones: tocar un viaje abre su detalle.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final membership = session.selectedMembership;
    return AppScaffold(
      title: 'Viajes',
      tab: MainTab.trips,
      body: AsyncView<TripsData>(
        key: ValueKey('${membership?.workerId}-${membership?.itineraryId}'),
        load: () => TripsData.load(context, membership),
        builder: (context, data, reload) {
          final me = session.me!;
          Widget card(Trip trip) => TripCard(
                trip: trip,
                legs: data.legs[trip.id],
                running: data.running.contains(trip),
                showOverload: me.can(Op.tripsEdit, entityId: trip.entityId, itineraryId: trip.itineraryId),
                onTap: () async {
                  await AppRoutes.tripDetail(context, trip.id);
                  reload();
                },
              );
          return ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), physics: const AlwaysScrollableScrollPhysics(), children: [
            const EntitySelector(),
            if (membership == null)
              const Padding(padding: EdgeInsets.all(24), child: Text('Cuando pertenezca a una Entidad verá aquí sus viajes.', textAlign: TextAlign.center))
            else if (data.running.isEmpty && data.confirmed.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No hay viajes en curso ni confirmados.', textAlign: TextAlign.center))
            else ...[
              if (data.running.isNotEmpty) ...[const SectionHeader('En curso'), for (final trip in data.running) card(trip)],
              if (data.confirmed.isNotEmpty) ...[const SectionHeader('Confirmados'), for (final trip in data.confirmed) card(trip)],
            ],
          ]);
        },
      ),
    );
  }
}

/// Viajes de la Entidad elegida: en curso (con un trayecto activo) y
/// confirmados que aún no terminaron.
class TripsData {
  final List<Trip> running;
  final List<Trip> confirmed;
  final Map<String, List<TripLeg>> legs;

  const TripsData(this.running, this.confirmed, this.legs);

  static Future<TripsData> load(BuildContext context, Membership? membership) async {
    if (membership == null) return const TripsData([], [], {});
    final api = context.api;
    final now = DateTime.now();
    final trips = (await api.get('/trips', query: {
      'include': SyncService.tripInclude,
      'filter[status]': TripStatus.confirmed,
      'filter[from]': now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
      'sort': 'departsAt',
      'page[size]': 50,
    }))
        .resources
        .map(Trip.from)
        .where((trip) => trip.entityId == null || trip.entityId == membership.entityId)
        .toList();
    final legs = await TripContext.legsOf(api, trips);
    bool isRunning(Trip trip) => (legs[trip.id] ?? const []).any((leg) => leg.isActive);
    final running = trips.where(isRunning).toList();
    bool finished(Trip trip) => (legs[trip.id] ?? const []).any((leg) => leg.direction == 'return' && !leg.isActive);
    final confirmed = trips.where((trip) => !isRunning(trip) && !finished(trip) && trip.returnsAt.isAfter(now)).toList();
    return TripsData(running, confirmed, legs);
  }
}
