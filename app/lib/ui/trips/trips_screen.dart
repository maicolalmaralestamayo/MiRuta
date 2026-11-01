import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../widgets/common.dart';
import 'trip_card.dart';
import 'trip_context.dart';

/// Viajes: los de mi itinerario, los que conduzco y los de los itinerarios que dirijo.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final tabs = <(String, Map<String, dynamic>, bool)>[
      if (me.itineraryId != null) ('Mi itinerario', {'filter[itinerary]': me.itineraryId}, me.isChiefOf(me.itineraryId) || me.managesTransport),
      if (me.roles.isDriver) ('Como chofer', {'filter[driver]': me.roles.driverId}, true),
      if (me.roles.isItineraryChief || me.managesTransport) ('Todos los que veo', <String, dynamic>{}, true),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Viajes')),
        body: const EmptyView(icon: Icons.directions_bus_outlined, message: 'Cuando sea miembro de un itinerario verá aquí sus viajes.'),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Viajes'),
          bottom: tabs.length > 1 ? TabBar(isScrollable: true, tabs: [for (final tab in tabs) Tab(text: tab.$1)]) : null,
        ),
        body: TabBarView(children: [for (final tab in tabs) _TripList(filters: tab.$2, showOverload: tab.$3)]),
      ),
    );
  }
}

class _TripList extends StatefulWidget {
  final Map<String, dynamic> filters;
  final bool showOverload;

  const _TripList({required this.filters, required this.showOverload});

  @override
  State<_TripList> createState() => _TripListState();
}

class _TripListState extends State<_TripList> {
  bool _past = false;

  Future<(List<Trip>, Map<String, List<TripLeg>>)> _load() async {
    final today = DateTime.now();
    final query = {
      ...widget.filters,
      'include': SyncService.tripInclude,
      if (_past) 'filter[to]': today.toIso8601String().substring(0, 10),
      if (!_past) 'filter[from]': today.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
      'sort': _past ? '-departsAt' : 'departsAt',
      'page[size]': 50,
    };
    final api = context.api;
    final trips = (await api.get('/trips', query: query)).resources.map(Trip.from).toList();
    return (trips, await TripContext.legsOf(api, trips));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, icon: Icon(Icons.upcoming), label: Text('Próximos')), ButtonSegment(value: true, icon: Icon(Icons.history), label: Text('Anteriores'))],
          selected: {_past},
          onSelectionChanged: (value) => setState(() => _past = value.first),
        ),
      ),
      Expanded(
        child: AsyncView<(List<Trip>, Map<String, List<TripLeg>>)>(
          key: ValueKey(_past),
          load: _load,
          builder: (context, data, reload) => data.$1.isEmpty
              ? const EmptyView(icon: Icons.event_busy, message: 'No hay viajes.')
              : ListView.builder(
                  itemCount: data.$1.length,
                  itemBuilder: (context, index) {
                    final trip = data.$1[index];
                    return TripCard(trip: trip, legs: data.$2[trip.id], showOverload: widget.showOverload, onChanged: reload);
                  },
                ),
        ),
      ),
    ]);
  }
}
