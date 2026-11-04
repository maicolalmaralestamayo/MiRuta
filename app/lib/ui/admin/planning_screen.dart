import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/sync.dart';
import '../navigation.dart';
import '../trips/trip_card.dart';
import '../trips/trip_detail_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';
import 'trip_form_screen.dart';

/// Planificación de viajes (Gestión): el Jefe de Transporte en toda su
/// Entidad, el Jefe de itinerario en su itinerario y el Administrador. Viajes
/// por fechas e itinerario, con selección múltiple para confirmar,
/// desconfirmar, cancelar o eliminar, y avisos de sobresaturación y de
/// viajes sin chofer.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<List<Trip>>>();
  final _selection = SelectionController();
  late DateTimeRange _range;
  String? _itineraryId;
  List<Itinerary> _itineraries = [];
  List<Trip> _trips = const [];

  @override
  String get entityOperation => Op.tripsPlan;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range = DateTimeRange(start: DateTime(today.year, today.month, today.day), end: DateTime(today.year, today.month, today.day + 14));
    initEntity();
    if (entity != null) _loadItineraries();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  void onEntityChanged() {
    _selection.clear();
    _itineraryId = null;
    _loadItineraries();
    _view.currentState?.reload();
  }

  /// Planifica en toda la Entidad (no solo en su itinerario).
  bool get _wholeEntity => entity != null && context.me.can(Op.tripsPlan, entityId: entity!.id);

  void _loadItineraries() {
    final e = entity!;
    final me = context.me;
    context.api.getAll('/itineraries', query: {'sort': 'name', 'filter[entity]': e.id}).then((r) {
      if (!mounted) return;
      setState(() {
        _itineraries = r.map(Itinerary.from).where((i) => me.can(Op.tripsPlan, entityId: e.id, itineraryId: i.id)).toList();
        // Quien solo planifica su itinerario ve el suyo.
        if (!_wholeEntity && _itineraryId == null && _itineraries.isNotEmpty) {
          _itineraryId = _itineraries.first.id;
          _view.currentState?.reload();
        }
      });
    }).catchError((_) {});
  }

  String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<List<Trip>> _load() async {
    if (!_wholeEntity && _itineraryId == null) return _trips = const [];
    final resources = await context.api.getAll('/trips', query: {
      'include': SyncService.tripInclude,
      'filter[from]': _day(_range.start),
      'filter[to]': _day(_range.end),
      'filter[itinerary]': ?_itineraryId,
      'sort': 'departsAt',
    });
    final e = entity!;
    final trips = resources.map(Trip.from).where((t) => t.entityId == null || t.entityId == e.id).toList();
    _trips = trips;
    _selection.retain(trips.map((t) => t.id));
    return trips;
  }

  List<Trip> get _selected => _selection.selectedOf(_trips, (t) => t.id);

  Future<void> _bulk(String status) async {
    final operations = [
      for (final t in _selected) {'op': 'update', 'data': {'type': 'trips', 'id': t.id, 'attributes': {'status': status}}},
    ];
    try {
      await context.api.atomicOperations(operations);
      if (!mounted) return;
      showMessage(context, '${plural(operations.length, 'viaje', 'viajes')}: ${TripStatus.label(status).toLowerCase()}');
      _selection.clear();
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _delete() async {
    final api = context.api;
    final selected = _selected;
    if (await runAction(context, () async {
      for (final t in selected) {
        await api.delete('/trips/${t.id}');
      }
    }, success: selected.length == 1 ? 'Viaje eliminado.' : 'Viajes eliminados.')) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  Future<void> _form([Trip? trip]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TripFormScreen(trip: trip, entityId: entity?.id)));
    if (saved == true) _view.currentState?.reload();
  }

  bool _canOn(String op, Iterable<Trip> trips) => trips.isNotEmpty && trips.every((t) => context.me.can(op, entityId: entity?.id, itineraryId: t.itineraryId));

  @override
  Widget build(BuildContext context) {
    final e = entity;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selected = _selected;
        return AppScaffold(
          title: 'Planificación',
          tab: MainTab.more,
          selection: _selection,
          actions: e == null
              ? const []
              : [
                  ActionItem(icon: Icons.add, label: 'Crear viajes', onPressed: _form),
                  const ActionItem.divider(),
                  ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, enabled: _canOn(Op.tripsEdit, selected), onPressed: () => _form(selected.first)),
                  ActionItem(
                    icon: Icons.check_circle_outline,
                    label: 'Confirmar',
                    needs: ActionNeeds.some,
                    enabled: _canOn(Op.tripsConfirmCancel, selected),
                    onPressed: () => _bulk(TripStatus.confirmed),
                  ),
                  ActionItem(
                    icon: Icons.pending_outlined,
                    label: 'Marcar como no confirmados',
                    needs: ActionNeeds.some,
                    enabled: _canOn(Op.tripsConfirmCancel, selected),
                    onPressed: () => _bulk(TripStatus.unconfirmed),
                  ),
                  ActionItem(
                    icon: Icons.cancel_outlined,
                    label: 'Cancelar viajes',
                    needs: ActionNeeds.some,
                    enabled: _canOn(Op.tripsConfirmCancel, selected),
                    confirmation: '¿Cancelar ${plural(selected.length, 'viaje', 'viajes')}? Se avisará a los trabajadores.',
                    onPressed: () => _bulk(TripStatus.cancelled),
                  ),
                  ActionItem(
                    icon: Icons.delete_outline,
                    label: 'Eliminar',
                    needs: ActionNeeds.some,
                    destructive: true,
                    enabled: _canOn(Op.tripsDelete, selected),
                    confirmation: '¿Eliminar ${plural(selected.length, 'viaje', 'viajes')}? Los que ya empezaron no se pueden eliminar.',
                    onPressed: _delete,
                  ),
                ],
          body: entityPlaceholder() ??
              AsyncView<List<Trip>>(
                key: _view,
                load: _load,
                builder: (context, trips, reload) {
                  final overloaded = trips.where((t) => t.overloaded && t.status != TripStatus.cancelled).length;
                  final orphans = trips.where((t) => t.needsReassignment).length;
                  return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
                    entitySelector(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Column(children: [
                        DateRangeField(
                          label: 'Fechas',
                          value: _range,
                          firstDate: DateTime(2024),
                          onChanged: (range) {
                            setState(() => _range = range);
                            reload();
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          key: ValueKey('${e!.id}-${_itineraries.length}'),
                          initialValue: _itineraryId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Itinerario'),
                          items: [
                            if (_wholeEntity) const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                            for (final i in _itineraries) DropdownMenuItem<String?>(value: i.id, child: Text(i.name)),
                          ],
                          onChanged: (value) {
                            setState(() => _itineraryId = value);
                            reload();
                          },
                        ),
                      ]),
                    ),
                    if (overloaded > 0)
                      ListTile(leading: const Icon(Icons.warning_amber, color: Colors.red), title: Text(plural(overloaded, 'viaje sobresaturado', 'viajes sobresaturados'))),
                    if (orphans > 0)
                      ListTile(
                        leading: const Icon(Icons.person_off, color: Colors.red),
                        title: Text('${plural(orphans, 'viaje', 'viajes')} sin chofer: hay que reasignar${orphans == 1 ? 'lo' : 'los'}'),
                      ),
                    if (trips.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No hay viajes en estas fechas.', textAlign: TextAlign.center)),
                    for (final trip in trips)
                      SelectableCard(
                        controller: _selection,
                        selectionKey: trip.id,
                        onOpen: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)));
                          reload();
                        },
                        builder: (context, selected, onTap, onLongPress) => GestureDetector(
                          onLongPress: onLongPress,
                          child: TripCard(
                            trip: trip,
                            showOverload: true,
                            onTap: onTap,
                            leading: selected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                          ),
                        ),
                      ),
                  ]);
                },
              ),
        );
      },
    );
  }
}
