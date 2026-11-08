import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../core/storage.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import '../widgets/marks.dart';
import 'trip_card.dart';
import 'trip_form_screen.dart';
import 'trip_line_screen.dart';
import 'trip_workers_screen.dart';

/// Viajes (docs/11 §11.33 y §11.53, maqueta G18 n.º 8): selectores Entidad
/// e Itinerario y las secciones Planificados, En ejecución, Terminados y
/// Cancelados (estas dos se muestran u ocultan).
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  static const _key = 'user.viajes.selectors';
  final _view = GlobalKey<DataViewState<TripList>>();
  final _marks = Marks();
  String? _entity;
  String? _itinerary;
  bool _showFinished = true;
  bool _showCancelled = false;
  bool _ready = false;
  List<Entity> _entities = const [];
  List<Itinerary> _itineraries = const [];

  Me get _me => context.read<Session>().me!;

  @override
  void initState() {
    super.initState();
    Storage.getJson(_key).then((saved) {
      final me = _me;
      if (saved.isNotEmpty) {
        _entity = saved['entity'] as String?;
        _itinerary = saved['itinerary'] as String?;
        _showFinished = saved['finished'] != false;
        _showCancelled = saved['cancelled'] == true;
      } else {
        final m = me.chiefMembership ?? me.memberships.where((m) => m.itineraryId != null).firstOrNull ?? me.memberships.firstOrNull;
        _entity = m?.entityId;
        _itinerary = m?.itineraryId;
      }
      if (mounted) setState(() => _ready = true);
    });
  }

  void _save() => Storage.setString(_key, jsonEncode({'entity': _entity, 'itinerary': _itinerary, 'finished': _showFinished, 'cancelled': _showCancelled}));

  Future<TripList> _load() async {
    final api = context.read<Session>().api;
    final me = _me;
    if (!me.seesTrips) return const TripList([], {});
    _entities = (await api.getAll('/entities')).map(Entity.from).toList();
    if (_entity != null && !_entities.any((e) => e.id == _entity)) _entity = null;
    _itineraries = (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[entity]': ?_entity})).map(Itinerary.from).toList();
    if (_itinerary != null && !_itineraries.any((i) => i.id == _itinerary)) _itinerary = null;
    final statuses = [TripStatus.planned, TripStatus.running, if (_showFinished) TripStatus.finished, if (_showCancelled) TripStatus.cancelled];
    final list = await TripList.load(api, {'filter[status]': statuses.join(','), 'filter[itinerary]': ?_itinerary});
    final allowed = _itineraries.map((i) => i.id).toSet();
    if (mounted) setState(() {});
    return TripList(list.trips.where((t) => _entity == null || allowed.contains(t.itineraryId)).toList(), list.ends);
  }

  Future<void> _pickEntity() async {
    const all = Entity(id: '', abbreviation: 'Todas las Entidades');
    final e = await pickOne<Entity>(context, 'Entidad', [all, ..._entities], (e) => e.abbreviation, subtitle: (e) => e.name);
    if (e == null) return;
    setState(() {
      _entity = e.id.isEmpty ? null : e.id;
      _itinerary = null;
    });
    _save();
    _view.currentState?.reload();
  }

  Future<void> _pickItinerary() async {
    const all = Itinerary(id: '', name: 'Todos los itinerarios');
    final i = await pickOne<Itinerary>(context, 'Itinerario', [all, ..._itineraries], (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? '');
    if (i == null) return;
    setState(() => _itinerary = i.id.isEmpty ? null : i.id);
    _save();
    _view.currentState?.reload();
  }

  Future<void> _changeStatus(Trip trip, String status, String verb) async {
    if (!await confirm(context, verb, '¿$verb el ${trip.title.toLowerCase()} de ${trip.itineraryName ?? ''}?', accept: verb, icon: Icons.check, destructive: status == TripStatus.cancelled)) return;
    if (!mounted) return;
    if (await runAction(context, () => context.read<Session>().api.patch('/trips/${trip.id}', resourceData('trips', id: trip.id, attributes: {'status': status})), success: 'Hecho.')) {
      _marks.clear();
      _view.currentState?.reload();
    }
  }

  List<ActionItem> _actions() {
    final me = _me;
    final data = _view.currentState?.data;
    final canPlan = me.isAdmin || me.chiefItineraryId != null;
    if (!_marks.active) {
      return [
        if (canPlan) ActionItem(Icons.event_note, 'Planificar viaje', () async {
          await push(context, PlanTripScreen(itineraryId: me.isAdmin ? _itinerary : me.chiefItineraryId));
          _view.currentState?.reload();
        }),
        ActionItem(_showFinished ? Icons.visibility_off : Icons.visibility, '${_showFinished ? 'Ocultar' : 'Mostrar'} terminados', () {
          setState(() => _showFinished = !_showFinished);
          _save();
          _view.currentState?.reload();
        }),
        ActionItem(_showCancelled ? Icons.visibility_off : Icons.visibility, '${_showCancelled ? 'Ocultar' : 'Mostrar'} cancelados', () {
          setState(() => _showCancelled = !_showCancelled);
          _save();
          _view.currentState?.reload();
        }),
      ];
    }
    final trips = data?.trips ?? const <Trip>[];
    final marked = _marks.of('trip', trips, (t) => t.id);
    final one = marked.length == 1 ? marked.first : null;
    final manage = one != null && (me.isAdmin || me.isChiefOf(one.itineraryId));
    return [
      ...markActions(_marks, trips.map((t) => t.id)),
      if (one != null) ActionItem(Icons.edit_outlined, 'Editar', () => _openForm(one)),
      if (one != null) ActionItem(Icons.timeline, 'Ver recorrido', () => push(context, TripLineScreen(tripId: one.id))),
      if (one != null) ActionItem(Icons.groups_outlined, 'Trabajadores', () => push(context, TripWorkersScreen(trip: one))),
      if (manage && one.isPlanned) ActionItem(Icons.play_arrow, 'Empezar viaje', () => _changeStatus(one, TripStatus.running, 'Empezar')),
      if (manage && one.isRunning) ActionItem(Icons.flag_outlined, 'Terminar viaje', () => _changeStatus(one, TripStatus.finished, 'Terminar')),
      if (manage && one.isPlanned && (me.isAdmin || one.createdById == me.userId))
        ActionItem(Icons.cancel_outlined, 'Cancelar viaje', () => _changeStatus(one, TripStatus.cancelled, 'Cancelar'), destructive: true),
      if (marked.isNotEmpty && marked.every((t) => !t.isRunning && (me.isAdmin || me.isChiefOf(t.itineraryId))))
        ActionItem(Icons.delete_outline, 'Eliminar', () async {
          if (!await confirmDelete(context, marked.length == 1 ? 'el ${marked.first.title.toLowerCase()}' : '${marked.length} viajes', consequences: 'Se pierden sus estados y su recorrido.')) return;
          if (!mounted) return;
          final api = context.read<Session>().api;
          if (await runAction(context, () async {
            for (final t in marked) {
              await api.delete('/trips/${t.id}');
            }
          }, success: 'Eliminado.')) {
            _marks.clear();
            _view.currentState?.reload();
          }
        }, destructive: true),
    ];
  }

  Future<void> _openForm(Trip trip) async {
    await push(context, TripFormScreen(tripId: trip.id));
    _view.currentState?.reload();
  }

  Widget _card(TripList data, Trip t) => ListenableBuilder(
        listenable: _marks,
        builder: (context, _) => TripCard(
          trip: t,
          departure: data.departureOf(t),
          selected: _marks.isMarked('trip', t.id),
          onTap: () => _marks.active ? _marks.toggle('trip', t.id) : _openForm(t),
          onLongPress: () => _marks.toggle('trip', t.id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    if (!_ready) return const AppScaffold(title: 'Viajes', tab: MainTab.trips, body: Center(child: CircularProgressIndicator()));
    if (!me.seesTrips) {
      final m = me.memberships.firstOrNull;
      return AppScaffold.list(title: 'Viajes', tab: MainTab.trips, children: [
        NoticeCard(
          icon: Icons.directions_bus_outlined,
          title: 'Aún no ve viajes',
          detail: m == null
              ? 'Para ver los viajes necesita una Entidad, un itinerario y una parada.'
              : m.itineraryId == null
                  ? 'Para ver los viajes necesita un itinerario y una parada en ${m.entityAbbreviation}.'
                  : 'Para ver los viajes elija su parada en ${m.itineraryName}.',
          buttonIcon: Icons.settings,
          buttonText: 'Ir a Gestión',
          onPressed: () => MainTabs.go(context, MainTab.management),
        ),
      ]);
    }
    final entity = _entities.where((e) => e.id == _entity).firstOrNull;
    final itinerary = _itineraries.where((i) => i.id == _itinerary).firstOrNull;
    return AppScaffold(
      title: 'Viajes',
      tab: MainTab.trips,
      marks: _marks,
      actions: _actions,
      body: DataView<TripList>(
        key: _view,
        kinds: const {'trips'},
        cacheKey: 'viajes',
        load: _load,
        builder: (context, data, reload) {
          List<Trip> of(String status) => data.trips.where((t) => t.status == status).toList();
          return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
            SelectorCard(
              icon: Icons.apartment,
              title: entity?.abbreviation ?? 'Todas las Entidades',
              lines: ['Entidad', if (entity != null) _workers(entity.workerCount)],
              onTap: _pickEntity,
            ),
            SelectorCard(
              icon: Icons.route,
              title: itinerary?.name ?? 'Todos los itinerarios',
              lines: ['Itinerario', if (itinerary != null) '${itinerary.stopCount} paradas • ${_workers(itinerary.workerCount)}'],
              onTap: _pickItinerary,
            ),
            separator(),
            FoldSection<Trip>(storageKey: 'viajes.planificados', title: 'Planificados', items: of(TripStatus.planned), builder: (t) => _card(data, t), emptyText: 'No hay viajes planificados.'),
            FoldSection<Trip>(storageKey: 'viajes.ejecucion', title: 'En ejecución', items: of(TripStatus.running), builder: (t) => _card(data, t), emptyText: 'No hay viajes en ejecución.'),
            if (_showFinished) FoldSection<Trip>(storageKey: 'viajes.terminados', title: 'Terminados', items: of(TripStatus.finished).reversed.toList(), builder: (t) => _card(data, t), initiallyOpen: false),
            if (_showCancelled) FoldSection<Trip>(storageKey: 'viajes.cancelados', title: 'Cancelados', items: of(TripStatus.cancelled).reversed.toList(), builder: (t) => _card(data, t), initiallyOpen: false),
          ]);
        },
      ),
    );
  }
}

String _workers(int n) => n == 1 ? '1 trabajador' : '$n trabajadores';
