import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
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
import 'forms.dart';
import 'include_by_qr_screen.dart';
import 'ops.dart';

/// Datos de Gestión ya filtrados por los selectores.
class _Data {
  final List<Entity> entities;
  final List<Itinerary> itineraries;
  final List<Stop> stops;
  final List<Worker> people;
  final List<Application> applications;

  const _Data(this.entities, this.itineraries, this.stops, this.people, this.applications);
}

const _all = 'all';
const _none = 'none';

/// Gestión (docs/11 §11.26, maqueta G18 n.º 4): una sola pantalla con los
/// selectores Entidad → Itinerario → Parada, el buscador de personas y las
/// secciones plegables Entidades, Itinerarios, Paradas, Personas y
/// Solicitudes. Tocar = abrir el formulario; mantener = marcar; el menú
/// Acciones cambia según lo marcado.
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  static const _selectorsKey = 'user.gestion.selectors';

  final _view = GlobalKey<DataViewState<_Data>>();
  final _marks = Marks();
  final _search = TextEditingController();
  String _entity = _all;
  String _itinerary = _all;
  String _stop = _all;
  bool _showApproved = false;
  bool _showRejected = false;
  bool _ready = false;

  // Listas para los selectores (sin el filtro de su propio nivel).
  List<Entity> _entityOptions = const [];
  List<Itinerary> _itineraryOptions = const [];
  List<Stop> _stopOptions = const [];

  Me get _me => context.read<Session>().me!;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _marks.dispose();
    _search.dispose();
    super.dispose();
  }

  /// La última elección o, la primera vez, su Entidad, su itinerario y todas las paradas.
  Future<void> _restore() async {
    final saved = await Storage.getJson(_selectorsKey);
    if (saved.isNotEmpty) {
      _entity = '${saved['entity'] ?? _all}';
      _itinerary = '${saved['itinerary'] ?? _all}';
      _stop = '${saved['stop'] ?? _all}';
      _showApproved = saved['approved'] == true;
      _showRejected = saved['rejected'] == true;
    } else {
      final m = _me.chiefMembership ?? _me.memberships.firstOrNull;
      if (m != null) {
        _entity = m.entityId;
        _itinerary = m.itineraryId ?? _all;
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() => Storage.setString(_selectorsKey, jsonEncode({'entity': _entity, 'itinerary': _itinerary, 'stop': _stop, 'approved': _showApproved, 'rejected': _showRejected}));

  void _select({String? entity, String? itinerary, String? stop}) {
    setState(() {
      if (entity != null) {
        _entity = entity;
        _itinerary = _all;
        _stop = _all;
      }
      if (itinerary != null) {
        _itinerary = itinerary;
        _stop = _all;
      }
      if (stop != null) _stop = stop;
    });
    _marks.clear();
    _save();
    _view.currentState?.reload();
  }

  Future<void> _reload() async => _view.currentState?.reload();

  Future<_Data> _load() async {
    final session = context.read<Session>();
    final api = session.api;
    final me = _me;
    final entities = (await api.getAll('/entities')).map(Entity.from).toList();
    if (_entity != _all && _entity != _none && !entities.any((e) => e.id == _entity)) _entity = _all;
    if (_entity == _none && !me.isAdmin) _entity = _all;
    final entityId = _entity == _all || _entity == _none ? null : _entity;

    final itineraries = _entity == _none
        ? <Itinerary>[]
        : (await api.getAll('/itineraries', query: {'include': 'entity', 'filter[entity]': ?entityId})).map(Itinerary.from).toList();
    if (_itinerary != _all && _itinerary != _none && !itineraries.any((i) => i.id == _itinerary)) {
      _itinerary = _all;
      _stop = _all;
    }
    final itineraryId = _itinerary == _all || _itinerary == _none ? null : _itinerary;

    final List<Stop> stops;
    if (itineraryId != null) {
      stops = (await api.getAll('/stops', query: {'filter[itinerary]': itineraryId, 'sort': 'position'})).map(Stop.from).toList();
    } else if (_itinerary == _none) {
      stops = (await api.getAll('/stops', query: {'filter[itinerary]': _none})).map(Stop.from).toList();
    } else if (_entity == _none) {
      stops = const [];
    } else {
      stops = (await api.getAll('/stops', query: {'filter[entity]': ?entityId})).map(Stop.from).toList();
    }
    if (_stop != _all && _stop != _none && !stops.any((s) => s.id == _stop)) _stop = _all;

    final search = _search.text.trim();
    final List<Worker> people;
    if (_entity == _none) {
      people = (await api.getAll('/users', query: {'filter[entity]': _none, if (search.isNotEmpty) 'filter[search]': search})).map(Person.from).map(Worker.withoutEntity).toList();
    } else {
      people = (await api.getAll('/workers', query: {
        'include': 'user,entity,itinerary,stop',
        'filter[entity]': ?entityId,
        if (_itinerary != _all) 'filter[itinerary]': _itinerary,
        if (_stop != _all) 'filter[stop]': _stop,
        if (search.isNotEmpty) 'filter[search]': search,
      }))
          .map(Worker.from)
          .toList();
    }

    final statuses = ['pendiente', if (_showApproved) 'aprobada', if (_showRejected) 'rechazada'];
    final applications = (await api.getAll('/applications', query: {
      'include': 'user,entity,itinerary,stop,denialReason,resolvedBy',
      'filter[status]': statuses.join(','),
      'filter[entity]': ?entityId,
      'filter[itinerary]': ?itineraryId,
    }))
        .map(Application.from)
        .toList();

    // Abrió Gestión con solicitudes resueltas sin ver: quedan vistas.
    if ((session.counters['applicationsResolvedUnseen'] ?? 0) > 0) {
      api.post('/me/applications-seen', const {}).then((_) => session.sync()).catchError((_) {});
    }

    _entityOptions = entities;
    _itineraryOptions = itineraries;
    _stopOptions = stops;
    if (mounted) setState(() {});
    return _Data(
      entityId == null ? (_entity == _none ? const [] : entities) : entities.where((e) => e.id == entityId).toList(),
      itineraryId == null ? (_itinerary == _none ? const [] : itineraries) : itineraries.where((i) => i.id == itineraryId).toList(),
      _stop == _all ? stops : (_stop == _none ? const [] : stops.where((s) => s.id == _stop).toList()),
      people,
      applications,
    );
  }

  // Selectores

  Future<void> _pickEntity() async {
    const allOption = Entity(id: _all, abbreviation: 'Todas las Entidades');
    const noneOption = Entity(id: _none, abbreviation: 'Sin Entidad');
    final picked = await pickOne<Entity>(context, 'Entidad', [allOption, if (_me.isAdmin) noneOption, ..._entityOptions], (e) => e.abbreviation,
        subtitle: (e) => e.id == _all || e.id == _none ? '' : e.name, selected: [allOption, noneOption, ..._entityOptions].where((e) => e.id == _entity).firstOrNull);
    if (picked != null) _select(entity: picked.id);
  }

  Future<void> _pickItinerary() async {
    const allOption = Itinerary(id: _all, name: 'Todos los itinerarios');
    const noneOption = Itinerary(id: _none, name: 'Sin itinerario');
    final options = [allOption, noneOption, ..._itineraryOptions];
    final picked = await pickOne<Itinerary>(context, 'Itinerario', options, (i) => i.name,
        subtitle: (i) => i.entityAbbreviation ?? '', selected: options.where((i) => i.id == _itinerary).firstOrNull);
    if (picked != null) _select(itinerary: picked.id);
  }

  Future<void> _pickStop() async {
    const allOption = Stop(id: _all, landmark: 'Todas las paradas');
    const noneOption = Stop(id: _none, landmark: 'Sin parada');
    final options = [allOption, noneOption, ..._stopOptions];
    final picked = await pickOne<Stop>(context, 'Parada', options, (s) {
      final position = s.positionIn(_itinerary);
      return position == null ? s.landmark : '$position. ${s.landmark}';
    }, subtitle: (s) => s.address, selected: options.where((s) => s.id == _stop).firstOrNull, search: _stopOptions.length > 8);
    if (picked != null) _select(stop: picked.id);
  }

  List<Widget> _selectors() {
    final workers = _entityOptions.fold<int>(0, (sum, e) => sum + e.workerCount);
    final entity = _entityOptions.where((e) => e.id == _entity).firstOrNull;
    final itinerary = _itineraryOptions.where((i) => i.id == _itinerary).firstOrNull;
    final stop = _stopOptions.where((s) => s.id == _stop).firstOrNull;
    return [
      SelectorCard(
        icon: Icons.apartment,
        title: entity?.abbreviation ?? (_entity == _none ? 'Sin Entidad' : 'Todas las Entidades'),
        lines: entity != null
            ? ['Entidad', plural(entity.workerCount, 'trabajador', 'trabajadores')]
            : ['Entidad', if (_entity != _none) '${plural(_entityOptions.length, 'Entidad', 'Entidades')} • ${plural(workers, 'trabajador', 'trabajadores')}'],
        onTap: _pickEntity,
      ),
      if (_entity != _none)
        SelectorCard(
          icon: Icons.route,
          title: itinerary?.name ?? (_itinerary == _none ? 'Sin itinerario' : 'Todos los itinerarios'),
          lines: itinerary != null
              ? ['Itinerario', '${plural(itinerary.stopCount, 'parada', 'paradas')} • ${plural(itinerary.workerCount, 'trabajador', 'trabajadores')}']
              : ['Itinerario', if (_itinerary == _all) plural(_itineraryOptions.length, 'itinerario', 'itinerarios')],
          onTap: _pickItinerary,
        ),
      if (_entity != _none)
        SelectorCard(
          icon: Icons.place,
          title: stop == null ? (_stop == _none ? 'Sin parada' : 'Todas las paradas') : '${stop.positionIn(_itinerary) == null ? '' : '${stop.positionIn(_itinerary)}. '}${stop.landmark}',
          lines: ['Parada', if (stop == null && _stop == _all) plural(_stopOptions.length, 'parada', 'paradas') else if (stop != null) stop.address],
          onTap: _pickStop,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _reload(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar persona (nombre, carné o usuario)',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      _reload();
                    }),
          ),
        ),
      ),
      separator(),
    ];
  }

  // Tarjetas

  Widget _markable(String type, String key, Widget Function(bool marked, VoidCallback onTap, VoidCallback onLongPress) builder, VoidCallback open) {
    return ListenableBuilder(
      listenable: _marks,
      builder: (context, _) {
        final marked = _marks.isMarked(type, key);
        return builder(marked, () => _marks.active && _marks.type == type ? _marks.toggle(type, key) : open(), () => _marks.toggle(type, key));
      },
    );
  }

  Widget _entityCard(Entity e) => _markable('entity', e.id, (marked, tap, long) => InfoCard(
        images: [CardImage(url: e.imageUrl, icon: Icons.apartment, dim: !e.active)],
        title: e.abbreviation,
        lines: [e.name, '${plural(e.itineraryCount, 'itinerario', 'itinerarios')} • ${plural(e.workerCount, 'trabajador', 'trabajadores')}'],
        chip: e.active ? null : const Chip2('Desactivado', grey),
        dim: !e.active,
        selected: marked,
        onTap: tap,
        onLongPress: long,
      ), () => _open(EntityForm(entity: e)));

  Widget _itineraryCard(Itinerary i) => _markable('itinerary', i.id, (marked, tap, long) => InfoCard(
        images: [CardImage(url: i.imageUrl, icon: Icons.route, dim: !i.active)],
        title: i.name,
        lines: ['${_entity == _all && i.entityAbbreviation != null ? '${i.entityAbbreviation} • ' : ''}${plural(i.stopCount, 'parada', 'paradas')} • ${plural(i.workerCount, 'trabajador', 'trabajadores')}'],
        chip: !i.active ? const Chip2('Desactivado', grey) : (_me.isChiefOf(i.id) ? const Chip2('Jefe', green) : null),
        dim: !i.active,
        selected: marked,
        onTap: tap,
        onLongPress: long,
      ), () => _open(ItineraryForm(itinerary: i)));

  Widget _stopCard(Stop s, {Widget? trailing}) => _markable('stop', s.id, (marked, tap, long) {
        final position = s.positionIn(_itinerary);
        return InfoCard(
          images: [CardImage(url: s.imageUrl, icon: Icons.place, dim: !s.active)],
          title: position == null ? s.landmark : '$position. ${s.landmark}',
          lines: [s.address, s.itineraries.isEmpty ? 'Sin itinerario' : s.itineraries.map((l) => l.name).join(', ')],
          chip: s.active ? null : const Chip2('Desactivada', grey),
          dim: !s.active,
          selected: marked,
          trailing: trailing,
          onTap: tap,
          onLongPress: long,
        );
      }, () => _open(StopForm(stop: s)));

  Widget _personCard(Worker w) => _markable('person', w.key, (marked, tap, long) {
        final where = !w.hasMembership
            ? 'Sin Entidad'
            : [
                if (_entity == _all) w.entityAbbreviation ?? '',
                w.itineraryName ?? 'Sin itinerario',
                if (w.itineraryId != null) w.stopLandmark ?? 'Sin parada',
              ].where((p) => p.isNotEmpty).join(' • ');
        return InfoCard(
          images: [CardImage(url: w.person.photoUrl, icon: Icons.person, round: true, dim: !w.active)],
          title: w.person.fullName,
          lines: [where],
          chip: !w.active ? const Chip2('Desactivado', grey) : (w.isChief ? const Chip2('Jefe', green) : (w.person.isAdmin ? const Chip2('Admin.', blue2) : null)),
          dim: !w.active,
          selected: marked,
          onTap: tap,
          onLongPress: long,
        );
      }, () => _open(WorkerForm(worker: w)));

  Widget _applicationCard(Application a) => _markable('application', a.id, (marked, tap, long) {
        final mine = a.userId == _me.userId;
        final color = switch (a.status) { 'aprobada' => green, 'rechazada' => red, _ => amber };
        return InfoCard(
          images: [CardImage(icon: a.isEntity ? Icons.apartment : Icons.route)],
          title: mine ? a.what : (a.userName ?? 'Solicitud'),
          lines: [
            if (!mine) a.what,
            mine ? 'Mi solicitud • ${formatDate(a.createdAt)}' : formatDate(a.createdAt),
            if (a.status == 'rechazada' && a.denialReason != null) 'Motivo: ${a.denialReason}',
          ],
          chip: Chip2(a.statusName, color),
          selected: marked,
          onTap: tap,
          onLongPress: long,
        );
      }, () => _showApplication(a));

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    if (mounted) _reload();
  }

  Future<void> _showApplication(Application a) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Solicitud de ${a.isEntity ? 'Entidad' : 'itinerario'}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Persona: ${a.userName ?? ''}'),
            Text('Solicita: ${a.what}'),
            Text('Fecha: ${formatDateTime(a.createdAt)}'),
            Text('Estado: ${a.statusName}'),
            if (a.resolvedAt != null) Text('Resuelta: ${formatDateTime(a.resolvedAt)}${a.resolvedBy == null ? '' : ' por ${a.resolvedBy}'}'),
            if (a.denialReason != null) Text('Motivo: ${a.denialReason}'),
            if (a.resolutionNote != null && a.resolutionNote!.isNotEmpty) Text('Observación: ${a.resolutionNote}'),
          ]),
          actions: [TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('Cerrar'))],
        ),
      );

  // Paradas del itinerario elegido: se ordenan arrastrando.
  Widget _orderableStops(List<Stop> stops) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) async {
        final ordered = [...stops];
        ordered.insert(to, ordered.removeAt(from));
        final ok = await runAction(context, () => context.read<Session>().api.patch('/itineraries/$_itinerary/relationships/stops', {
              'data': [for (final s in ordered) ResourceId('stops', s.id).toJson()],
            }));
        if (ok) _reload();
      },
      children: [
        for (var i = 0; i < stops.length; i++)
          KeyedSubtree(
            key: ValueKey(stops[i].id),
            child: _stopCard(stops[i], trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle))),
          ),
      ],
    );
  }

  // Acciones

  List<ActionItem> _actions(_Data? data, bool offline) {
    final me = _me;
    final ops = Ops(context);
    final admin = me.isAdmin;
    final manages = me.manages;
    final type = _marks.type;
    Future<void> done(Future<bool> Function() f) async {
      if (await f()) {
        _marks.clear();
        await _reload();
        if (mounted) await context.read<Session>().reloadMe();
      }
    }

    if (data == null) return const [];
    final qr = manages ? [ActionItem(Icons.qr_code_scanner, 'Incluir por QR', () => _open(const IncludeByQrScreen()))] : <ActionItem>[];
    if (offline) return [...qr, const ActionItem.divider(), ActionItem(Icons.refresh, 'Reintentar', _reload)];

    if (!_marks.active) {
      final selectedEntity = data.entities.length == 1 && _entity != _all ? data.entities.first : null;
      final selectedItinerary = data.itineraries.length == 1 && _itinerary != _all ? data.itineraries.first : null;
      return [
        if (admin) ActionItem(Icons.person_add_alt_1, 'Registrar trabajador', () => _open(RegisterWorkerForm(entity: selectedEntity))),
        if (admin) ActionItem(Icons.add_business_outlined, 'Crear Entidad', () => _open(const EntityForm())),
        if (admin) ActionItem(Icons.add_road, 'Crear itinerario', () => _createItinerary(selectedEntity)),
        if (admin || me.chiefItineraryId != null) ActionItem(Icons.add_location_alt_outlined, 'Crear parada', () => _createStop(selectedItinerary)),
        ...qr,
        if (admin) ActionItem(Icons.login, 'Entrar en una Entidad', () => done(() => _joinEntity(data))),
        if (!admin) ActionItem(Icons.apartment, 'Solicitar Entidad', () => done(ops.requestEntity)),
        if (!admin && me.hasEntity) ActionItem(Icons.route, 'Solicitar Itinerario', () => done(() => ops.requestItinerary(me))),
        if (me.hasEntity) ActionItem(Icons.event_busy, 'Declarar ausencia', _declareOwnAbsence),
        const ActionItem.divider(),
        ActionItem(_showApproved ? Icons.visibility_off : Icons.visibility, '${_showApproved ? 'Ocultar' : 'Mostrar'} solicitudes aprobadas', () {
          setState(() => _showApproved = !_showApproved);
          _save();
          _reload();
        }),
        ActionItem(_showRejected ? Icons.visibility_off : Icons.visibility, '${_showRejected ? 'Ocultar' : 'Mostrar'} solicitudes rechazadas', () {
          setState(() => _showRejected = !_showRejected);
          _save();
          _reload();
        }),
      ];
    }

    final one = _marks.one;
    switch (type) {
      case 'entity':
        final marked = _marks.of('entity', data.entities, (e) => e.id);
        final first = marked.firstOrNull;
        return [
          ...markActions(_marks, data.entities.map((e) => e.id)),
          if (one && first != null) ActionItem(Icons.edit_outlined, 'Editar', () => _open(EntityForm(entity: first))),
          if (one && admin && first != null) ActionItem(Icons.add_road, 'Crear itinerario', () => _createItinerary(first)),
          if (one && first != null && me.membershipIn(first.id) != null)
            ActionItem(Icons.logout, 'Salir de la Entidad', () => done(() => _leaveEntity(me.membershipIn(first.id)!))),
          if (admin) ActionItem(Icons.delete_outline, 'Eliminar', () => done(() => _delete('entities', marked.map((e) => e.id), marked.length == 1 ? 'la Entidad ${marked.first.abbreviation}' : '${marked.length} Entidades',
              'Se eliminan sus itinerarios (con sus viajes y solicitudes). Las personas no se eliminan: quedan sin esa Entidad. Las paradas se conservan.')), destructive: true),
        ];
      case 'itinerary':
        final marked = _marks.of('itinerary', data.itineraries, (i) => i.id);
        final first = marked.firstOrNull;
        final manage = first != null && (admin || me.isChiefOf(first.id));
        final membership = first == null ? null : me.memberships.where((m) => m.itineraryId == first.id).firstOrNull;
        return [
          ...markActions(_marks, data.itineraries.map((i) => i.id)),
          if (one && first != null) ActionItem(Icons.edit_outlined, 'Editar', () => _open(ItineraryForm(itinerary: first))),
          if (one && manage) ActionItem(Icons.add_location_alt_outlined, 'Crear parada', () => _createStop(first)),
          if (one && manage) ActionItem(Icons.playlist_add, 'Añadir parada existente', () => done(() => _addExistingStop(first))),
          if (admin) ActionItem(Icons.swap_horiz, 'Cambiar de Entidad', () => done(() => _moveItineraries(marked))),
          if (one && admin && first != null) ActionItem(Icons.badge_outlined, 'Asignar Jefe de itinerario', () => done(() => _assignChiefTo(first))),
          if (one && membership != null) ActionItem(Icons.logout, 'Salir del itinerario', () => done(() => _leaveItinerary(membership))),
          if (one && !admin && first != null && membership == null && me.membershipIn(first.entityId) != null)
            ActionItem(Icons.send, 'Solicitar este itinerario', () => done(() => ops.requestItinerary(me, itinerary: first))),
          if (admin) ActionItem(Icons.delete_outline, 'Eliminar', () => done(() => _delete('itineraries', marked.map((i) => i.id), marked.length == 1 ? 'el itinerario ${marked.first.name}' : '${marked.length} itinerarios',
              'Sus personas quedan sin itinerario, parada ni jefatura; se eliminan sus viajes. Las paradas se conservan.')), destructive: true),
        ];
      case 'stop':
        final marked = _marks.of('stop', data.stops, (s) => s.id);
        final first = marked.firstOrNull;
        final itineraryId = _itinerary == _all || _itinerary == _none ? null : _itinerary;
        final manageItinerary = itineraryId != null && (admin || me.isChiefOf(itineraryId));
        final myMembership = first == null ? null : me.memberships.where((m) => m.itineraryId != null && first.positionIn(m.itineraryId) != null).firstOrNull;
        return [
          ...markActions(_marks, data.stops.map((s) => s.id)),
          if (one && first != null) ActionItem(Icons.edit_outlined, 'Editar', () => _open(StopForm(stop: first))),
          if (admin || me.chiefItineraryId != null) ActionItem(Icons.playlist_add, 'Añadir a un itinerario', () => done(() => _addStopsTo(marked))),
          if (manageItinerary) ActionItem(Icons.playlist_remove, 'Quitar del itinerario', () => done(() => _removeFromItinerary(marked, itineraryId))),
          if (one && myMembership != null && myMembership.stopId != first!.id)
            ActionItem(Icons.where_to_vote_outlined, 'Cambiarme a esta parada', () => done(() => _moveMeTo(myMembership, first))),
          if (admin || me.chiefItineraryId != null)
            ActionItem(Icons.delete_outline, 'Eliminar', () => done(() => _delete('stops', marked.map((s) => s.id), marked.length == 1 ? 'la parada ${marked.first.landmark}' : '${marked.length} paradas',
                'Quien la tenía queda sin parada (conserva su itinerario). Si la usa otro itinerario, el Jefe solo puede quitarla del suyo.')), destructive: true),
        ];
      case 'person':
        final marked = _marks.of('person', data.people, (w) => w.key);
        final first = marked.firstOrNull;
        final members = marked.where((w) => w.hasMembership).toList();
        final chiefScope = !admin && members.every((w) => w.itineraryId != null && me.isChiefOf(w.itineraryId));
        final sameEntity = members.map((w) => w.entityId).toSet().length == 1;
        return [
          ...markActions(_marks, data.people.map((w) => w.key)),
          if (one && first != null) ActionItem(Icons.edit_outlined, 'Editar', () => _open(WorkerForm(worker: first))),
          if (one && admin && first != null && first.hasMembership && !first.isChief) ActionItem(Icons.badge_outlined, 'Asignar rol', () => done(() => ops.assignChief(first))),
          if (one && admin && first != null && first.isChief)
            ActionItem(Icons.remove_moderator_outlined, 'Quitar rol de Jefe', () => done(() async {
                  await context.read<Session>().api.patch('/workers/${first.id}', resourceData('workers', id: first.id, attributes: {'isChief': false}));
                  return true;
                })),
          if (admin) ActionItem(Icons.swap_horiz, 'Cambiar de Entidad', () => done(() => ops.changeEntity(marked))),
          if (members.length == marked.length && sameEntity && (admin || me.chiefItineraryId != null))
            ActionItem(Icons.alt_route, 'Cambiar de itinerario', () => done(() => ops.changeItinerary(me, members))),
          if (one && first != null && first.hasMembership && first.itineraryId != null && (admin || chiefScope))
            ActionItem(Icons.where_to_vote_outlined, 'Cambiar de parada', () => done(() => ops.changeStop(first))),
          if (one && first != null && first.hasMembership && (admin || chiefScope))
            ActionItem(Icons.event_busy, 'Declarar ausencia', () => done(() => ops.declareAbsence(first.id, who: first.person.fullName))),
          if (admin && members.isNotEmpty)
            ActionItem(Icons.person_remove_outlined, 'Sacar de la Entidad', () => done(() => _delete('workers', members.map((w) => w.id), members.length == 1 ? 'a ${members.first.person.fullName} de ${members.first.entityAbbreviation ?? 'la Entidad'}' : 'a ${members.length} personas de su Entidad',
                'Pierden allí su itinerario, parada, jefatura, ausencias y solicitudes pendientes. La persona no se elimina.', verb: 'Sacar')), destructive: true),
          if (admin)
            ActionItem(Icons.delete_outline, 'Eliminar', () => done(() => _delete('users', marked.map((w) => w.person.id).toSet(), marked.length == 1 ? 'a ${marked.first.person.fullName}' : 'a ${marked.length} personas',
                'Se elimina la persona con su cuenta, sus pertenencias y sus solicitudes. No afecta a lo demás.')), destructive: true),
        ];
      case 'application':
        final marked = _marks.of('application', data.applications, (a) => a.id);
        final mine = marked.every((a) => a.userId == me.userId);
        final pending = marked.every((a) => a.pending);
        final resolvable = manages && pending && marked.every((a) => a.userId != me.userId && (admin || (!a.isEntity && me.isChiefOf(a.itineraryId))));
        return [
          ...markActions(_marks, data.applications.map((a) => a.id)),
          if (resolvable) ActionItem(Icons.check_circle_outline, 'Aprobar', () => done(() async {
                await ops.approve(marked);
                return true;
              })),
          if (resolvable) ActionItem(Icons.block, 'Rechazar', () => done(() => ops.reject(marked)), destructive: true),
          if (mine && pending) ActionItem(Icons.cancel_outlined, 'Cancelar', () => done(() => _delete('applications', marked.map((a) => a.id), marked.length == 1 ? 'la solicitud' : '${marked.length} solicitudes', null, verb: 'Cancelar'))),
          if (mine && marked.every((a) => !a.pending))
            ActionItem(Icons.delete_outline, 'Eliminar', () => done(() => _delete('applications', marked.map((a) => a.id), marked.length == 1 ? 'la solicitud' : '${marked.length} solicitudes', null)), destructive: true),
        ];
    }
    return const [];
  }

  Future<bool> _delete(String type, Iterable<String> ids, String what, String? consequences, {String verb = 'Eliminar'}) async {
    final ok = verb == 'Eliminar'
        ? await confirmDelete(context, what, consequences: consequences)
        : await confirm(context, verb, '¿$verb $what?${consequences == null ? '' : '\n\n$consequences'}', accept: verb, icon: Icons.check, destructive: true);
    if (!ok || !mounted) return false;
    final api = context.read<Session>().api;
    for (final id in ids) {
      await api.delete('/$type/$id');
    }
    if (mounted) showMessage(context, 'Hecho.');
    return true;
  }

  Future<void> _createItinerary(Entity? entity) async {
    var target = entity;
    if (target == null) {
      target = await pickOne<Entity>(context, 'Crear itinerario en…', _entityOptions, (e) => e.abbreviation, subtitle: (e) => e.name);
      if (target == null) return;
    }
    await _open(ItineraryForm(entityId: target.id));
  }

  Future<void> _createStop(Itinerary? itinerary) async {
    final me = _me;
    String? itineraryId = itinerary?.id;
    if (!me.isAdmin) itineraryId = me.chiefItineraryId;
    await _open(StopForm(itineraryId: itineraryId));
  }

  Future<bool> _joinEntity(_Data data) async {
    final candidates = _entityOptions.where((e) => _me.membershipIn(e.id) == null).toList();
    final entity = await pickOne<Entity>(context, 'Entrar en una Entidad', candidates, (e) => e.abbreviation, subtitle: (e) => e.name);
    if (entity == null || !mounted) return false;
    await context.read<Session>().api.post('/workers', resourceData('workers', relationships: {
      'entity': ResourceId('entities', entity.id),
      'user': ResourceId('users', _me.userId),
    }));
    return true;
  }

  Future<bool> _leaveEntity(Membership m) async {
    if (!await confirm(context, 'Salir de la Entidad', '¿Salir de ${m.entityAbbreviation}? Perderá allí su itinerario, parada, jefatura y solicitudes pendientes.', accept: 'Salir', icon: Icons.logout, destructive: true)) {
      return false;
    }
    if (!mounted) return false;
    await context.read<Session>().api.delete('/workers/${m.workerId}');
    return true;
  }

  Future<bool> _leaveItinerary(Membership m) async {
    final warning = m.isChief ? ' Perderá el rol de Jefe de itinerario.' : '';
    if (!await confirm(context, 'Salir del itinerario', '¿Salir de ${m.itineraryName}? Quedará sin itinerario ni parada en ${m.entityAbbreviation}.$warning',
        accept: 'Salir', icon: Icons.logout, destructive: true)) {
      return false;
    }
    if (!mounted) return false;
    await context.read<Session>().api.patch('/workers/${m.workerId}', resourceData('workers', id: m.workerId, relationships: {'itinerary': null}));
    return true;
  }

  Future<bool> _moveMeTo(Membership m, Stop stop) async {
    await context.read<Session>().api.patch('/workers/${m.workerId}', resourceData('workers', id: m.workerId, relationships: {'stop': ResourceId('stops', stop.id)}));
    if (mounted) showMessage(context, 'Su parada ahora es ${stop.landmark}.');
    return true;
  }

  Future<void> _declareOwnAbsence() async {
    final me = _me;
    var membership = me.memberships.first;
    if (me.memberships.length > 1) {
      final picked = await pickOne<Membership>(context, 'Ausencia en…', me.memberships, (m) => m.entityAbbreviation, subtitle: (m) => m.itineraryName ?? 'Sin itinerario');
      if (picked == null) return;
      membership = picked;
    }
    if (mounted) await Ops(context).declareAbsence(membership.workerId);
  }

  Future<bool> _moveItineraries(List<Itinerary> itineraries) async {
    final entity = await pickOne<Entity>(context, 'Cambiar de Entidad', _entityOptions, (e) => e.abbreviation, subtitle: (e) => e.name);
    if (entity == null || !mounted) return false;
    if (!await confirm(context, 'Cambiar de Entidad', 'Las personas de ${itineraries.length == 1 ? 'ese itinerario' : 'esos itinerarios'} quedarán sin itinerario. ¿Seguir?', accept: 'Cambiar', icon: Icons.swap_horiz)) {
      return false;
    }
    if (!mounted) return false;
    final api = context.read<Session>().api;
    for (final i in itineraries) {
      await api.patch('/itineraries/${i.id}', resourceData('itineraries', id: i.id, relationships: {'entity': ResourceId('entities', entity.id)}));
    }
    return true;
  }

  Future<bool> _assignChiefTo(Itinerary itinerary) async {
    final api = context.read<Session>().api;
    final people = (await api.getAll('/workers', query: {'include': 'user,itinerary', 'filter[entity]': ?itinerary.entityId})).map(Worker.from).toList();
    if (!mounted) return false;
    final worker = await pickOne<Worker>(context, 'Jefe de ${itinerary.name}', people, (w) => w.person.fullName, subtitle: (w) => w.itineraryName ?? 'Sin itinerario', search: true);
    if (worker == null || !mounted) return false;
    if (worker.itineraryId != itinerary.id &&
        !await confirm(context, 'Asignar Jefe de itinerario', 'El Jefe viaja en su itinerario: ${worker.person.fullName} pasará a ${itinerary.name}. ¿Seguir?', accept: 'Asignar', icon: Icons.badge_outlined)) {
      return false;
    }
    await api.patch('/workers/${worker.id}', resourceData('workers', id: worker.id, attributes: {'isChief': true}, relationships: {
      if (worker.itineraryId != itinerary.id) 'itinerary': ResourceId('itineraries', itinerary.id),
    }));
    return true;
  }

  Future<bool> _addExistingStop(Itinerary itinerary) async {
    final api = context.read<Session>().api;
    final all = (await api.getAll('/stops')).map(Stop.from).where((s) => s.positionIn(itinerary.id) == null).toList();
    if (!mounted) return false;
    final stop = await pickOne<Stop>(context, 'Añadir parada existente', all, (s) => s.landmark, subtitle: (s) => s.address, search: true);
    if (stop == null) return false;
    await api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
      'itinerary': ResourceId('itineraries', itinerary.id),
      'stop': ResourceId('stops', stop.id),
    }));
    return true;
  }

  Future<bool> _addStopsTo(List<Stop> stops) async {
    final me = _me;
    final options = me.isAdmin ? _itineraryOptions : _itineraryOptions.where((i) => i.id == me.chiefItineraryId).toList();
    final itinerary = await pickOne<Itinerary>(context, 'Añadir a un itinerario', options, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? '');
    if (itinerary == null || !mounted) return false;
    final api = context.read<Session>().api;
    for (final s in stops.where((s) => s.positionIn(itinerary.id) == null)) {
      await api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
        'itinerary': ResourceId('itineraries', itinerary.id),
        'stop': ResourceId('stops', s.id),
      }));
    }
    return true;
  }

  Future<bool> _removeFromItinerary(List<Stop> stops, String itineraryId) async {
    if (!await confirm(context, 'Quitar del itinerario', '¿Quitar ${stops.length == 1 ? 'la parada ${stops.first.landmark}' : '${stops.length} paradas'} del itinerario? La parada se conserva; quien la tenía en este itinerario queda sin parada.',
        accept: 'Quitar', icon: Icons.playlist_remove, destructive: true)) {
      return false;
    }
    if (!mounted) return false;
    final api = context.read<Session>().api;
    for (final s in stops) {
      final link = s.linkIn(itineraryId);
      if (link != null) await api.delete('/itinerary-stops/${link.itineraryStopId}');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const AppScaffold(title: 'Gestión', tab: MainTab.management, body: Center(child: CircularProgressIndicator()));
    final me = context.watch<Session>().me!;
    return AppScaffold(
      title: 'Gestión',
      tab: MainTab.management,
      marks: _marks,
      actions: () => _actions(_view.currentState?.data, _view.currentState?.offline ?? false),
      body: DataView<_Data>(
        key: _view,
        kinds: const {'applications'},
        cacheKey: 'gestion',
        load: _load,
        builder: (context, data, reload) {
          final itineraryId = _itinerary == _all || _itinerary == _none ? null : _itinerary;
          final draggable = itineraryId != null && _stop == _all && (me.isAdmin || me.isChiefOf(itineraryId)) && data.stops.length > 1;
          return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
            ..._selectors(),
            if (_entity != _none) FoldSection<Entity>(storageKey: 'gestion.entidades', title: 'Entidades', items: data.entities, builder: _entityCard),
            if (_entity != _none) FoldSection<Itinerary>(storageKey: 'gestion.itinerarios', title: 'Itinerarios', items: data.itineraries, builder: _itineraryCard),
            if (_entity != _none)
              FoldSection<Stop>(
                storageKey: 'gestion.paradas',
                title: 'Paradas',
                items: data.stops,
                builder: (s) => _stopCard(s),
                paginate: itineraryId == null,
                child: draggable ? _orderableStops(data.stops) : null,
              ),
            FoldSection<Worker>(storageKey: 'gestion.personas', title: 'Personas', items: data.people, builder: _personCard),
            FoldSection<Application>(storageKey: 'gestion.solicitudes', title: 'Solicitudes', items: data.applications, builder: _applicationCard, emptyText: 'No hay solicitudes pendientes.'),
          ]);
        },
      ),
    );
  }
}
