import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/sync.dart';
import '../trips/trip_card.dart';
import '../widgets/common.dart';
import 'trip_form_screen.dart';

/// Planificación: viajes por fechas e itinerario, con selección múltiple para
/// confirmar, desconfirmar o cancelar, y avisos de sobresaturación y de
/// viajes sin chofer.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  final _view = GlobalKey<AsyncViewState<List<Trip>>>();
  late DateTimeRange _range;
  String? _itineraryId;
  List<Itinerary> _itineraries = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range = DateTimeRange(start: DateTime(today.year, today.month, today.day), end: DateTime(today.year, today.month, today.day + 14));
    final me = context.me;
    // Quien solo planifica su itinerario (trips.plan con ámbito itinerario) ve el suyo.
    final own = me.permissions.itinerariesFor(Op.tripsPlan);
    if (!_plansWholeEntities(me) && own.isNotEmpty) _itineraryId = own.first;
    context.api.getAll('/itineraries', query: {'sort': 'name', ...context.entityFilter}).then((r) {
      if (mounted) setState(() => _itineraries = r.map(Itinerary.from).where((i) => me.can(Op.tripsPlan, entityId: i.entityId, itineraryId: i.id)).toList());
    }).catchError((_) {});
  }

  /// Planifica en Entidades enteras (no solo en su itinerario).
  bool _plansWholeEntities(Me me) => me.permissions.entitiesFor(Op.tripsPlan)?.isNotEmpty ?? true;

  String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<List<Trip>> _load() async {
    final resources = await context.api.getAll('/trips', query: {
      'include': SyncService.tripInclude,
      'filter[from]': _day(_range.start),
      'filter[to]': _day(_range.end),
      if (_itineraryId != null) 'filter[itinerary]': _itineraryId,
      'sort': 'departsAt',
    });
    return resources.map(Trip.from).toList();
  }

  Future<void> _bulk(String status) async {
    final operations = [
      for (final id in _selected) {'op': 'update', 'data': {'type': 'trips', 'id': id, 'attributes': {'status': status}}},
    ];
    try {
      await context.api.atomicOperations(operations);
      if (!mounted) return;
      showMessage(context, '${plural(operations.length, 'viaje', 'viajes')}: ${TripStatus.label(status).toLowerCase()}');
      setState(_selected.clear);
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Planificación' : plural(_selected.length, 'seleccionado', 'seleccionados')),
        actions: _selected.isEmpty
            ? null
            : [
                IconButton(tooltip: 'Confirmar viajes', icon: const Icon(Icons.check_circle_outline), onPressed: () => _bulk(TripStatus.confirmed)),
                IconButton(tooltip: 'Marcar como no confirmados', icon: const Icon(Icons.pending_outlined), onPressed: () => _bulk(TripStatus.unconfirmed)),
                IconButton(
                  tooltip: 'Cancelar viajes',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: () async {
                    if (await confirm(context, 'Cancelar viajes', '¿Cancelar ${plural(_selected.length, 'viaje', 'viajes')}? Se avisará a los trabajadores.',
                        accept: 'Cancelar viajes', destructive: true)) {
                      _bulk(TripStatus.cancelled);
                    }
                  },
                ),
                IconButton(tooltip: 'Quitar selección', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nuevo viaje'),
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const TripFormScreen()));
          if (created == true) _view.currentState?.reload();
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: DateRangeField(
                label: 'Fechas',
                value: _range,
                firstDate: DateTime(2024),
                onChanged: (range) {
                  setState(() => _range = range);
                  _view.currentState?.reload();
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: DropdownButtonFormField<String?>(
                initialValue: _itineraryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Itinerario'),
                items: [
                  if (_plansWholeEntities(context.me)) const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                  for (final i in _itineraries) DropdownMenuItem<String?>(value: i.id, child: Text(i.name)),
                ],
                onChanged: (value) {
                  setState(() => _itineraryId = value);
                  _view.currentState?.reload();
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Trip>>(
            key: _view,
            load: _load,
            builder: (context, trips, reload) {
              if (trips.isEmpty) return const EmptyView(icon: Icons.event_note, message: 'No hay viajes en estas fechas.');
              final overloaded = trips.where((t) => t.overloaded && t.status != TripStatus.cancelled).length;
              final orphans = trips.where((t) => t.needsReassignment).length;
              return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                if (overloaded > 0)
                  ListTile(leading: const Icon(Icons.warning_amber, color: Colors.red), title: Text(plural(overloaded, 'viaje sobresaturado', 'viajes sobresaturados'))),
                if (orphans > 0)
                  ListTile(leading: const Icon(Icons.person_off, color: Colors.red), title: Text('${plural(orphans, 'viaje', 'viajes')} sin chofer: hay que reasignar${orphans == 1 ? 'lo' : 'los'}')),
                for (final trip in trips)
                  TripCard(
                    trip: trip,
                    showOverload: true,
                    onChanged: reload,
                    leading: Checkbox(
                      value: _selected.contains(trip.id),
                      onChanged: (value) => setState(() => value == true ? _selected.add(trip.id) : _selected.remove(trip.id)),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
