import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/children_api.dart';
import '../../services/qr/qr_codes.dart';
import '../../services/qr/qr_store.dart';
import '../navigation.dart';
import '../qr/boarding_scan.dart';
import '../qr/pending_scans_screen.dart';
import '../trips/trip_context.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';

/// Pasajeros de un trayecto: por parada (en el orden del trayecto) y, al
/// final, quienes subieron sin ser esperados (de otro itinerario o Entidad),
/// con los hijos que subieron. Acciones: escanear el QR (subida), subida
/// manual y, con tracking.fix_passengers, corregir los hijos o quitar la subida.
class PassengersScreen extends StatefulWidget {
  final TripContext context;
  final String direction;
  final TripLeg? leg;

  const PassengersScreen({super.key, required this.context, this.direction = 'return', this.leg});

  @override
  State<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends State<PassengersScreen> {
  late String _direction = widget.direction;
  final _selection = SelectionController();
  // Una vista por sentido: al cambiar de sentido se cargan sus pasajeros.
  final _views = {'outbound': GlobalKey<AsyncViewState<List<Passenger>>>(), 'return': GlobalKey<AsyncViewState<List<Passenger>>>()};
  List<Passenger> _passengers = const [];
  ScanRoster? _roster;
  int _pending = 0;

  TripContext get _trip => widget.context;

  TripLeg? get _leg => widget.leg?.direction == _direction ? widget.leg : _trip.leg(_direction);

  bool get _canFix => _trip.can(context.me, Op.trackingFixPassengers);

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
    _loadLocal();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    _selection.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final roster = await QrStore.roster(_trip.trip.entityId);
    final pending = await QrStore.pendingCount();
    if (mounted) {
      setState(() {
        _roster = roster;
        _pending = pending;
      });
    }
  }

  Future<List<Passenger>> _load() async {
    final document = await context.api.get('/trips/${_trip.trip.id}/passengers', query: {'filter[direction]': _direction});
    final passengers = document.resources.map(Passenger.from).toList();
    _passengers = passengers;
    _selection.retain(passengers.map(_key));
    return passengers;
  }

  void _reload() {
    _views[_direction]!.currentState?.reload();
    _loadLocal();
  }

  static String _key(Passenger p) => p.worker.id;

  List<Passenger> get _selected => _selection.selectedOf(_passengers, _key);

  /// Se puede registrar con el trayecto en curso, o terminado con tracking.fix_passengers.
  bool _canRegister(TripLeg? leg) => leg != null && (leg.isActive || _canFix);

  String _childName(String id) => _roster?.child(id)?.fullName ?? 'Niño n.º $id';

  /// Hijos con derecho de esa persona (de la lista guardada; si no está, de la API).
  Future<List<BoardingChildOption>> _childrenOf(Passenger p, Set<String> mine) async {
    final userId = p.worker.userId;
    if (userId == null) return const [];
    var children = _roster?.childrenOf(userId).map((c) => BoardingChildOption(id: c.childId, fullName: c.fullName, photoUrl: c.photoUrl)).toList();
    if (children == null || children.isEmpty) {
      try {
        children = [
          for (final c in await ChildrenApi(context.api).mine(userId, eligible: true, active: true))
            BoardingChildOption(id: c.id, fullName: c.name.full, photoUrl: c.photoUrl),
        ];
      } catch (_) {
        children = const [];
      }
    }
    // Los que ya subieron con otra persona en este trayecto no se pueden marcar.
    final taken = {for (final other in _passengers) if (other.worker.id != p.worker.id) ...other.boardedChildIds};
    return [
      for (final c in children)
        BoardingChildOption(id: c.id, fullName: c.fullName, photoUrl: c.photoUrl, alreadyBoarded: taken.contains(c.id) && !mine.contains(c.id)),
    ];
  }

  BoardingCandidate _candidate(Passenger p, List<BoardingChildOption> children) => BoardingCandidate(
        userId: p.worker.userId ?? '',
        fullName: p.worker.fullName,
        photoUrl: p.worker.photoUrl,
        lines: [if (_trip.stop(p.stopId) != null) _trip.stop(p.stopId)!.landmark],
        kind: QrKind.dynamic,
        children: children,
      );

  Future<void> _scan() async {
    final leg = _leg;
    if (!_canRegister(leg)) {
      showMessage(context, 'El ${TripLeg.directionName(_direction).toLowerCase()} no está en curso.');
      return;
    }
    await scanBoardings(context, _trip, leg!);
    if (mounted) _reload();
  }

  Future<void> _manual([Passenger? passenger]) async {
    final p = passenger ?? _selected.first;
    final leg = _leg;
    if (!_canRegister(leg)) {
      showMessage(context, 'El ${TripLeg.directionName(_direction).toLowerCase()} no está en curso.');
      return;
    }
    final children = await _childrenOf(p, const {});
    if (!mounted) return;
    final decision = await showBoardingSheet(context, _candidate(p, children), actionLabel: 'Registrar subida');
    if (decision == null || !mounted) return;
    await runAction(context, () async {
      await context.api.post(
          '/trip-boardings',
          resourceData('trip-boardings', attributes: {'method': 'manual', 'childIds': decision.childIds}, relationships: {
            'tripLeg': ResourceId('trip-legs', leg!.id),
            'worker': ResourceId('workers', p.worker.id),
          }));
      await QrStore.addLegBoarding(leg.id, userId: p.worker.userId ?? '', printed: false, childIds: decision.childIds);
    }, success: 'Subida registrada: ${p.worker.fullName}');
    _selection.clear();
    _reload();
  }

  Future<void> _fixChildren([Passenger? passenger]) async {
    final p = passenger ?? _selected.first;
    final id = p.tripBoardingId;
    if (id == null) return;
    final mine = p.boardedChildIds.toSet();
    final children = await _childrenOf(p, mine);
    if (!mounted) return;
    final decision = await showBoardingSheet(context, _candidate(p, children), initial: mine, actionLabel: 'Guardar hijos');
    if (decision == null || !mounted) return;
    await runAction(context, () => context.api.patch('/trip-boardings/$id', resourceData('trip-boardings', id: id, attributes: {'childIds': decision.childIds})),
        success: 'Hijos corregidos');
    _selection.clear();
    _reload();
  }

  Future<void> _removeBoardings() async {
    for (final p in _selected.where((p) => p.tripBoardingId != null)) {
      await context.api.delete('/trip-boardings/${p.tripBoardingId}');
    }
    _selection.clear();
    _reload();
  }

  Future<void> _open(Passenger p) async {
    final leg = _leg;
    final actions = <(IconData, String, Future<void> Function())>[
      if (!p.boarded && _canRegister(leg)) (Icons.how_to_reg, 'Registrar subida manual', () => _manual(p)),
      if (p.boarded && _canFix && p.tripBoardingId != null) (Icons.child_care, 'Corregir hijos que subieron', () => _fixChildren(p)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _card(p),
          for (final a in actions)
            ListTile(
              leading: Icon(a.$1),
              title: Text(a.$2),
              onTap: () {
                Navigator.pop(sheet);
                a.$3();
              },
            ),
          if (actions.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No hay acciones disponibles.')),
        ]),
      ),
    );
  }

  List<String> _lines(Passenger p) => [
        if (p.boarded)
          'Subió (${_method(p.boardingMethod)})'
              '${p.boardedChildIds.isNotEmpty ? ' con ${p.boardedChildIds.map(_childName).join(', ')}' : (p.boardedChildren ?? 0) > 0 ? ' con ${plural(p.boardedChildren!, 'niño', 'niños')}' : ''}'
        else
          'No ha subido',
        if (p.outsider != null) p.outsider == 'entity' ? 'De otra Entidad' : 'De otro itinerario',
        if ((p.eligibleChildren ?? 0) > 0) '${plural(p.eligibleChildren!, 'hijo', 'hijos')} con derecho',
      ];

  Widget _card(Passenger p, {bool selected = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
        images: [CardImage(url: p.worker.photoUrl, icon: Icons.person, round: true, size: 48)],
        title: p.worker.fullName,
        chip: p.boarded ? const CardChip('Subió') : (p.expected ? null : const CardChip('De fuera', color: Colors.orange)),
        lines: _lines(p),
        dim: !p.boarded,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );

  @override
  Widget build(BuildContext context) {
    final stops = _trip.orderedStops(_direction);
    final leg = _leg;
    final selected = _selected;
    final one = selected.length == 1 ? selected.first : null;
    return AppScaffold(
      title: 'Pasajeros',
      tab: MainTab.trips,
      selection: _selection,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'outbound', icon: Icon(Icons.north_east), label: Text('Viaje de ida')),
              ButtonSegment(value: 'return', icon: Icon(Icons.south_west), label: Text('Viaje de regreso')),
            ],
            selected: {_direction},
            onSelectionChanged: (value) {
              _selection.clear();
              setState(() => _direction = value.first);
            },
          ),
        ),
      ),
      actions: [
        ActionItem(icon: Icons.qr_code_scanner, label: 'Escanear QR (subida)', enabled: _canRegister(leg), onPressed: _scan),
        ActionItem(icon: Icons.cloud_upload_outlined, label: _pending > 0 ? 'Escaneos sin conexión ($_pending)' : 'Escaneos sin conexión', onPressed: () async {
          await openPendingScans(context);
          if (mounted) _reload();
        }),
        const ActionItem.divider(),
        ActionItem(
            icon: Icons.how_to_reg, label: 'Registrar subida manual', needs: ActionNeeds.one, enabled: one != null && !one.boarded && _canRegister(leg), onPressed: _manual),
        ActionItem(
            icon: Icons.child_care,
            label: 'Corregir hijos',
            needs: ActionNeeds.one,
            enabled: _canFix && one != null && one.boarded && one.tripBoardingId != null,
            onPressed: _fixChildren),
        ActionItem(
          icon: Icons.person_remove_outlined,
          label: 'Quitar subida',
          needs: ActionNeeds.some,
          destructive: true,
          enabled: _canFix && selected.isNotEmpty && selected.every((p) => p.boarded && p.tripBoardingId != null),
          confirmation: '¿Quitar la subida de los pasajeros seleccionados? Se quitan también los hijos que subieron con ellos.',
          onPressed: _removeBoardings,
        ),
      ],
      body: AsyncView<List<Passenger>>(
        key: _views[_direction],
        load: _load,
        builder: (context, passengers, reload) {
          final boarded = passengers.where((p) => p.boarded).length;
          final expected = passengers.where((p) => p.expected).length;
          final children = passengers.fold<int>(0, (sum, p) => sum + (p.boardedChildIds.isNotEmpty ? p.boardedChildIds.length : (p.boardedChildren ?? 0)));
          final outsiders = passengers.where((p) => !p.expected || p.stopId == null || _trip.stop(p.stopId) == null).toList();
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: SelectableCardList<Passenger>(
              controller: _selection,
              header: [
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text('$boarded subieron · ${plural(expected, 'esperado', 'esperados')}'),
                  subtitle: Text([
                    if (children > 0) 'Subieron ${plural(children, 'niño', 'niños')}',
                    if (outsiders.isNotEmpty) '${outsiders.length} de fuera',
                    if (_pending > 0) '${plural(_pending, 'escaneo', 'escaneos')} sin enviar',
                    if (leg == null) 'Sin empezar' else if (!leg.isActive) 'Trayecto terminado',
                  ].join(' · ')),
                ),
              ],
              sections: [
                for (final stop in stops) CardSection(title: stop.landmark, items: passengers.where((p) => p.expected && p.stopId == stop.id).toList()),
                CardSection(title: 'Subieron sin ser esperados', items: outsiders),
              ],
              keyOf: _key,
              onOpen: _open,
              cardBuilder: (context, p, selected, onTap, onLongPress) => _card(p, selected: selected, onTap: onTap, onLongPress: onLongPress),
            ),
          );
        },
      ),
    );
  }

  String _method(String? method) => const {'automatic': 'automática', 'self': 'Ya subí', 'qr': 'QR', 'manual': 'manual'}[method] ?? '';
}
