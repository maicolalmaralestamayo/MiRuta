import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../applications/application_forms.dart';
import '../profile/notices_screen.dart';
import '../trips/trip_card.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<_HomeData> _load(BuildContext context) async {
    final api = context.api;
    final me = context.me;
    final now = DateTime.now();
    final query = {
      'include': SyncService.tripInclude,
      'filter[status]': 'confirmed',
      'filter[from]': now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
      'sort': 'departsAt',
      'page[size]': 20,
    };
    final trips = (await api.get('/trips', query: query)).resources.map(Trip.from)
        .where((trip) => trip.returnsAt.isAfter(now) && (trip.itineraryId == me.itineraryId || trip.driverId == me.roles.driverId))
        .toList();
    final unread = (await api.get('/notices', query: {'filter[unread]': 'true', 'page[size]': 1})).total;
    final toResolve = (await api.get('/applications', query: {'filter[toResolve]': 'true', 'page[size]': 1})).total;
    Itinerary? itinerary;
    Stop? stop;
    if (me.itineraryId != null) {
      itinerary = Itinerary.from((await api.get('/itineraries/${me.itineraryId}')).resource);
      stop = Stop.from((await api.get('/stops/${me.stopId}')).resource);
    }
    return _HomeData(trips, unread, toResolve, itinerary, stop);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${me.firstName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen())),
          ),
        ],
      ),
      body: AsyncView<_HomeData>(
        key: ValueKey(me.itineraryId),
        load: () => _load(context),
        builder: (context, data, reload) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (data.itinerary == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.route),
                title: const Text('Aún no tienes itinerario'),
                subtitle: const Text('Solicita tu itinerario y tu parada para empezar a recibir los avisos.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await showApplicationForm(context, ApplicationType.itineraryMembership);
                  reload();
                },
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.route),
                title: Text(data.itinerary!.name),
                subtitle: Text('Tu parada: ${data.stop?.landmark ?? ''}\n${data.stop?.address ?? ''}'),
                isThreeLine: true,
              ),
            ),
          if (data.unread > 0 || data.toResolve > 0)
            Card(
              child: Column(children: [
                if (data.toResolve > 0)
                  ListTile(
                    leading: const Icon(Icons.pending_actions),
                    title: Text('${data.toResolve} solicitud(es) por resolver'),
                    subtitle: const Text('En la pestaña Solicitudes'),
                  ),
                if (data.unread > 0)
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text('${data.unread} aviso(s) sin leer'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen()));
                      reload();
                    },
                  ),
              ]),
            ),
          const SectionTitle('Próximos viajes'),
          if (data.trips.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No tienes viajes confirmados próximamente.'))
          else
            for (final trip in data.trips.take(5)) TripCard(trip: trip, showOverload: me.managesTransport || me.isChiefOf(trip.itineraryId), onChanged: reload),
        ]),
      ),
    );
  }
}

class _HomeData {
  final List<Trip> trips;
  final int unread;
  final int toResolve;
  final Itinerary? itinerary;
  final Stop? stop;

  _HomeData(this.trips, this.unread, this.toResolve, this.itinerary, this.stop);
}
