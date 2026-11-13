import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
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
import 'tiles.dart';

/// Base de las pantallas de cada tabla de Gestión (docs/11 §11.57 y §11.59,
/// maqueta G20 n.º 2 a 4): buscador, sus objetos en tarjetas de 5 en 5, los
/// sueltos que correspondan, el mecanismo de marcar de siempre y el botón
/// Acciones según lo marcado. Tocar un objeto abre su formulario.
abstract class _TableState<W extends StatefulWidget, D> extends State<W> {
  final view = GlobalKey<DataViewState<D>>();
  final marks = Marks();
  final search = TextEditingController();

  String get title;

  String get searchHint;

  Future<D> load();

  List<ActionItem> actions(D data);

  List<Widget> sections(D data);

  Me get me => context.read<Session>().me!;

  @override
  void dispose() {
    marks.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> reload() async => view.currentState?.reload();

  String get query => search.text.trim();

  /// Abre un formulario y, al volver, recarga.
  Future<void> openScreen(Future<Object?> Function() opener) async {
    await opener();
    if (mounted) await reload();
  }

  /// Operación sobre lo marcado: al terminar bien, desmarca y recarga.
  Future<void> doneWith(Future<bool> Function() action) async {
    if (await action() && mounted) {
      marks.clear();
      await reload();
      if (mounted) await context.read<Session>().reloadMe().catchError((_) {});
    }
  }

  /// Tarjeta que se marca (mantener) o se abre (tocar).
  Widget markable(String type, String key, Widget Function(bool marked, VoidCallback onTap, VoidCallback onLongPress) builder, VoidCallback open) {
    return ListenableBuilder(
      listenable: marks,
      builder: (context, _) {
        final marked = marks.isMarked(type, key);
        return builder(marked, () => marks.active && marks.type == type ? marks.toggle(type, key) : open(), () => marks.toggle(type, key));
      },
    );
  }

  Future<bool> deleteAll(String type, Iterable<String> ids, String what, String? consequences, String doneText) async {
    if (!await confirmDelete(context, what, consequences: consequences) || !mounted) return false;
    final api = context.api;
    for (final id in ids) {
      await api.delete('/$type/$id');
    }
    if (mounted) Ops(context).done(doneText);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      tab: MainTab.management,
      marks: marks,
      actions: () {
        final data = view.currentState?.data;
        if (data == null) return const [];
        if (view.currentState!.offline) {
          return [
            if (me.manages) ActionItem(Icons.qr_code_scanner, 'Incluir por QR', () => openScreen(() => push(context, const IncludeByQrScreen()))),
            ActionItem(Icons.refresh, 'Reintentar', reload),
          ];
        }
        return actions(data);
      },
      body: DataView<D>(
        key: view,
        kinds: const {'applications'},
        cacheKey: 'gestion.$title',
        load: load,
        builder: (context, data, _) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 120), physics: const AlwaysScrollableScrollPhysics(), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => reload(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: searchHint,
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          search.clear();
                          reload();
                        }),
              ),
            ),
          ),
          ...sections(data),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entidades (y trabajadores sin Entidad)
// ---------------------------------------------------------------------------

class _EntitiesData {
  final List<Entity> entities;
  final List<Person> loose;

  const _EntitiesData(this.entities, this.loose);
}

class EntitiesScreen extends StatefulWidget {
  const EntitiesScreen({super.key});

  @override
  State<EntitiesScreen> createState() => _EntitiesScreenState();
}

class _EntitiesScreenState extends _TableState<EntitiesScreen, _EntitiesData> {
  @override
  String get title => 'Entidades';

  @override
  String get searchHint => 'Buscar Entidad o persona';

  @override
  Future<_EntitiesData> load() async {
    final api = context.read<Session>().api;
    final entities = (await api.getAll('/entities', query: {if (query.isNotEmpty) 'filter[search]': query})).map(Entity.from).toList();
    final loose = me.isAdmin
        ? (await api.getAll('/users', query: {'filter[entity]': 'none', if (query.isNotEmpty) 'filter[search]': query})).map(Person.from).toList()
        : <Person>[];
    marks.retain('entity', entities.map((e) => e.id));
    marks.retain('person', loose.map((p) => p.id));
    return _EntitiesData(entities, loose);
  }

  @override
  List<Widget> sections(_EntitiesData data) => [
        FoldSection<Entity>(
          storageKey: 'gestion.entidades',
          title: 'Entidades',
          items: data.entities,
          emptyText: 'No hay Entidades.',
          builder: (e) => markable('entity', e.id, (m, tap, long) => entityTile(e, selected: m, onTap: tap, onLongPress: long),
              () => openScreen(() => push(context, EntityForm(entity: e)))),
        ),
        if (me.isAdmin)
          FoldSection<Person>(
            storageKey: 'gestion.sin_entidad',
            title: 'Trabajadores sin Entidad',
            items: data.loose,
            emptyText: 'Todos tienen Entidad.',
            builder: (p) => markable('person', p.id, (m, tap, long) => personTile(p, selected: m, onTap: tap, onLongPress: long),
                () => openScreen(() => openWorker(context, p.id, person: p))),
          ),
      ];

  @override
  List<ActionItem> actions(_EntitiesData data) {
    final admin = me.isAdmin;
    if (!marks.active) {
      return [
        if (admin) ActionItem(Icons.add_business_outlined, 'Crear Entidad', () => openScreen(() => push(context, const EntityForm()))),
        if (admin) ActionItem(Icons.person_add_alt_1, 'Registrar trabajador', () => openScreen(() => push(context, const RegisterWorkerForm()))),
        if (!admin) ActionItem(Icons.add_business_outlined, 'Solicitar Entidad', () => doneWith(Ops(context).requestEntity)),
      ];
    }
    if (marks.type == 'entity') {
      final marked = marks.of('entity', data.entities, (e) => e.id);
      return [
        ...markActions(marks, data.entities.map((e) => e.id)),
        if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => push(context, EntityForm(entity: marked.first)))),
        if (admin)
          ActionItem(Icons.delete_outline, 'Eliminar', () => doneWith(() => deleteAll('entities', marked.map((e) => e.id),
              marked.length == 1 ? 'la Entidad ${marked.first.abbreviation}' : '${marked.length} Entidades',
              'Sus itinerarios se conservan, sin Entidad. Las personas no se eliminan: quedan sin esa Entidad.', marked.length == 1 ? 'Entidad eliminada' : 'Entidades eliminadas')),
              destructive: true),
      ];
    }
    final marked = marks.of('person', data.loose, (p) => p.id);
    return [
      ...markActions(marks, data.loose.map((p) => p.id)),
      if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => openWorker(context, marked.first.id, person: marked.first))),
      if (admin) ActionItem(Icons.add_business_outlined, 'Asociar Entidad', () => doneWith(() => Ops(context).associateEntity(marked.map((p) => p.id).toList()))),
      if (admin)
        ActionItem(Icons.delete_outline, 'Eliminar', () => doneWith(() => deleteAll('users', marked.map((p) => p.id), marked.length == 1 ? 'a ${marked.first.fullName}' : 'a ${marked.length} personas',
            'Se elimina la persona con su cuenta y sus solicitudes.', marked.length == 1 ? 'Persona eliminada' : 'Personas eliminadas')), destructive: true),
    ];
  }
}

// ---------------------------------------------------------------------------
// Itinerarios (itinerarios sin Entidad y trabajadores sin itinerario)
// ---------------------------------------------------------------------------

class _ItinerariesData {
  final List<Itinerary> itineraries;
  final List<Itinerary> loose;
  final List<Worker> withoutItinerary;

  const _ItinerariesData(this.itineraries, this.loose, this.withoutItinerary);
}

class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends _TableState<ItinerariesScreen, _ItinerariesData> {
  @override
  String get title => 'Itinerarios';

  @override
  String get searchHint => 'Buscar itinerario o persona';

  @override
  Future<_ItinerariesData> load() async {
    final api = context.read<Session>().api;
    final search = {if (query.isNotEmpty) 'filter[search]': query};
    final all = (await api.getAll('/itineraries', query: {'include': 'entity', ...search})).map(Itinerary.from).toList();
    final people = me.manages
        ? (await api.getAll('/workers', query: {'filter[itinerary]': 'none', 'include': 'user,entity', ...search})).map(Worker.from).toList()
        : <Worker>[];
    final itineraries = all.where((i) => i.entityId != null).toList();
    final loose = all.where((i) => i.entityId == null).toList();
    marks.retain('itinerary', all.map((i) => i.id));
    marks.retain('worker', people.map((w) => w.id));
    return _ItinerariesData(itineraries, loose, people);
  }

  Widget _tile(Itinerary i) => markable('itinerary', i.id, (m, tap, long) => itineraryTile(i, selected: m, chief: me.isChiefOf(i.id), onTap: tap, onLongPress: long),
      () => openScreen(() => push(context, ItineraryForm(itinerary: i))));

  @override
  List<Widget> sections(_ItinerariesData data) => [
        FoldSection<Itinerary>(storageKey: 'gestion.itinerarios', title: 'Itinerarios', items: data.itineraries, emptyText: 'No hay itinerarios.', builder: _tile),
        if (me.isAdmin) FoldSection<Itinerary>(storageKey: 'gestion.itinerarios_sin_entidad', title: 'Itinerarios sin Entidad', items: data.loose, emptyText: 'Todos tienen Entidad.', builder: _tile),
        if (me.manages)
          FoldSection<Worker>(
            storageKey: 'gestion.sin_itinerario',
            title: 'Trabajadores sin itinerario',
            items: data.withoutItinerary,
            emptyText: 'Todos tienen itinerario.',
            builder: (w) => markable('worker', w.id, (m, tap, long) => workerTile(w, showEntity: true, selected: m, onTap: tap, onLongPress: long),
                () => openScreen(() => openWorker(context, w.person.id, person: w.person))),
          ),
      ];

  Future<bool> _changeEntity(List<Itinerary> itineraries) async {
    final list = await Ops(context).entities();
    if (!mounted) return false;
    const none = Entity(id: '', abbreviation: 'Sin Entidad');
    final entity = await pickOne<Entity>(context, 'Cambiar de Entidad', [none, ...list], (e) => e.abbreviation, subtitle: (e) => e.name);
    if (entity == null || !mounted) return false;
    if (!await confirm(context, 'Cambiar de Entidad',
        entity.id.isEmpty ? 'Sin Entidad, sus personas saldrán de ${itineraries.length == 1 ? 'él' : 'ellos'}. ¿Seguir?' : 'Sus personas pasarán con ${itineraries.length == 1 ? 'él' : 'ellos'} a ${entity.abbreviation}. ¿Seguir?',
        accept: 'Cambiar', icon: Icons.swap_horiz, headerIcon: Icons.apartment)) {
      return false;
    }
    if (!mounted) return false;
    final api = context.api;
    for (final i in itineraries) {
      await api.patch('/itineraries/${i.id}', resourceData('itineraries', id: i.id, relationships: {'entity': entity.id.isEmpty ? null : ResourceId('entities', entity.id)}));
    }
    if (mounted) Ops(context).done(itineraries.length == 1 ? 'Itinerario actualizado' : 'Itinerarios actualizados');
    return true;
  }

  @override
  List<ActionItem> actions(_ItinerariesData data) {
    final admin = me.isAdmin;
    final all = [...data.itineraries, ...data.loose];
    if (!marks.active) {
      return [
        if (admin) ActionItem(Icons.add_road, 'Crear itinerario', () => openScreen(() => push(context, const ItineraryForm()))),
        if (!admin && me.hasEntity) ActionItem(Icons.alt_route, 'Solicitar itinerario', () => doneWith(() => Ops(context).requestItinerary(me))),
      ];
    }
    if (marks.type == 'itinerary') {
      final marked = marks.of('itinerary', all, (i) => i.id);
      final first = marked.firstOrNull;
      final mine = first == null ? null : me.placementIn(first.id);
      return [
        ...markActions(marks, all.map((i) => i.id)),
        if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => push(context, ItineraryForm(itinerary: first)))),
        if (admin) ActionItem(Icons.swap_horiz, 'Cambiar de Entidad', () => doneWith(() => _changeEntity(marked))),
        if (marks.one && !admin && first != null && mine == null && first.entityId != null && me.membershipIn(first.entityId) != null)
          ActionItem(Icons.send, 'Solicitar este itinerario', () => doneWith(() => Ops(context).requestItinerary(me, itinerary: first))),
        if (marks.one && mine != null) ActionItem(Icons.logout, 'Salir del itinerario', () => doneWith(() => Ops(context).removeFromItinerary(mine))),
        if (admin)
          ActionItem(Icons.delete_outline, 'Eliminar', () => doneWith(() => deleteAll('itineraries', marked.map((i) => i.id),
              marked.length == 1 ? 'el itinerario ${marked.first.name}' : '${marked.length} itinerarios',
              'Sus personas salen de él; se eliminan sus viajes y solicitudes. Las paradas se conservan.', marked.length == 1 ? 'Itinerario eliminado' : 'Itinerarios eliminados')),
              destructive: true),
      ];
    }
    final marked = marks.of('worker', data.withoutItinerary, (w) => w.id);
    return [
      ...markActions(marks, data.withoutItinerary.map((w) => w.id)),
      if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => openWorker(context, marked.first.person.id, person: marked.first.person))),
      if (marks.one) ActionItem(Icons.add_road, 'Añadir itinerario', () => doneWith(() => Ops(context).addItinerary(me, marked.first.person.id, entityId: marked.first.entityId))),
    ];
  }
}

// ---------------------------------------------------------------------------
// Paradas (paradas sin itinerario y trabajadores sin parada)
// ---------------------------------------------------------------------------

class _StopsData {
  final List<Stop> stops;
  final List<Stop> loose;
  final List<Placement> withoutStop;

  const _StopsData(this.stops, this.loose, this.withoutStop);
}

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key});

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends _TableState<StopsScreen, _StopsData> {
  @override
  String get title => 'Paradas';

  @override
  String get searchHint => 'Buscar parada o persona';

  @override
  Future<_StopsData> load() async {
    final api = context.read<Session>().api;
    final search = {if (query.isNotEmpty) 'filter[search]': query};
    final all = (await api.getAll('/stops', query: search)).map(Stop.from).toList();
    final people = me.manages ? (await api.getAll('/worker-itineraries', query: {'filter[stop]': 'none', ...search})).map(Placement.from).toList() : <Placement>[];
    marks.retain('stop', all.map((s) => s.id));
    marks.retain('placement', people.map((p) => p.id));
    return _StopsData(all.where((s) => s.itineraries.isNotEmpty).toList(), all.where((s) => s.itineraries.isEmpty).toList(), people);
  }

  Widget _tile(Stop s) => markable('stop', s.id, (m, tap, long) => stopTile(s, selected: m, onTap: tap, onLongPress: long), () => openScreen(() => push(context, StopForm(stop: s))));

  @override
  List<Widget> sections(_StopsData data) => [
        FoldSection<Stop>(storageKey: 'gestion.paradas', title: 'Paradas', items: data.stops, emptyText: 'No hay paradas.', builder: _tile),
        if (me.manages) FoldSection<Stop>(storageKey: 'gestion.paradas_sin_itinerario', title: 'Paradas sin itinerario', items: data.loose, emptyText: 'Todas están en algún itinerario.', builder: _tile),
        if (me.manages)
          FoldSection<Placement>(
            storageKey: 'gestion.sin_parada',
            title: 'Trabajadores sin parada',
            items: data.withoutStop,
            emptyText: 'Todos tienen parada.',
            builder: (p) => markable('placement', p.id, (m, tap, long) => placementPersonTile(p, line: '${p.entityAbbreviation} • ${p.itineraryName}', selected: m, onTap: tap, onLongPress: long),
                () => openScreen(() => openWorker(context, p.userId ?? ''))),
          ),
      ];

  Future<bool> _associate(List<Stop> stops) async {
    var list = (await Ops(context).itineraries()).toList();
    if (!me.isAdmin) list = list.where((i) => i.id == me.chiefItineraryId).toList();
    if (!mounted) return false;
    final itinerary = await pickOne<Itinerary>(context, 'Asociar itinerario', list, (i) => i.name, subtitle: (i) => i.entityAbbreviation ?? 'Sin Entidad', search: list.length > 8);
    if (itinerary == null || !mounted) return false;
    final api = context.api;
    for (final s in stops.where((s) => s.positionIn(itinerary.id) == null)) {
      await api.post('/itinerary-stops', resourceData('itinerary-stops', relationships: {
        'itinerary': ResourceId('itineraries', itinerary.id),
        'stop': ResourceId('stops', s.id),
      }));
    }
    if (mounted) Ops(context).done('Itinerario asociado');
    return true;
  }

  @override
  List<ActionItem> actions(_StopsData data) {
    final admin = me.isAdmin;
    final chief = me.chiefItineraryId != null;
    final all = [...data.stops, ...data.loose];
    if (!marks.active) {
      return [
        if (admin || chief) ActionItem(Icons.add_location_alt_outlined, 'Crear parada', () => openScreen(() => push(context, StopForm(itineraryId: admin ? null : me.chiefItineraryId)))),
      ];
    }
    if (marks.type == 'stop') {
      final marked = marks.of('stop', all, (s) => s.id);
      final first = marked.firstOrNull;
      final mine = first == null ? null : me.placements.where((p) => first.positionIn(p.itineraryId) != null && p.stopId != first.id).firstOrNull;
      return [
        ...markActions(marks, all.map((s) => s.id)),
        if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => push(context, StopForm(stop: first)))),
        if (admin || chief) ActionItem(Icons.playlist_add, 'Asociar itinerario', () => doneWith(() => _associate(marked))),
        if (marks.one && mine != null)
          ActionItem(Icons.where_to_vote_outlined, 'Cambiarme a esta parada', () => doneWith(() async {
                await context.api.patch('/worker-itineraries/${mine.id}', resourceData('worker-itineraries', id: mine.id, relationships: {'stop': ResourceId('stops', first!.id)}));
                if (mounted) Ops(context).done('Parada cambiada');
                return true;
              })),
        if (admin || chief)
          ActionItem(Icons.delete_outline, 'Eliminar', () => doneWith(() => deleteAll('stops', marked.map((s) => s.id),
              marked.length == 1 ? 'la parada ${marked.first.landmark}' : '${marked.length} paradas',
              'Quien la tenía queda sin parada (conserva su itinerario). Si la usa otro itinerario, el Jefe solo puede quitarla del suyo.', marked.length == 1 ? 'Parada eliminada' : 'Paradas eliminadas')),
              destructive: true),
      ];
    }
    final marked = marks.of('placement', data.withoutStop, (p) => p.id);
    final first = marked.firstOrNull;
    return [
      ...markActions(marks, data.withoutStop.map((p) => p.id)),
      if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => openWorker(context, first!.userId ?? ''))),
      if (marks.one && first != null && (admin || me.isChiefOf(first.itineraryId)))
        ActionItem(Icons.where_to_vote_outlined, 'Elegir parada', () => doneWith(() => Ops(context).changeStop(first))),
    ];
  }
}

// ---------------------------------------------------------------------------
// Trabajadores
// ---------------------------------------------------------------------------

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends _TableState<WorkersScreen, List<Person>> {
  @override
  String get title => 'Trabajadores';

  @override
  String get searchHint => 'Buscar persona (nombre, carné o usuario)';

  @override
  Future<List<Person>> load() async {
    final people = (await context.read<Session>().api.getAll('/users', query: {if (query.isNotEmpty) 'filter[search]': query})).map(Person.from).toList();
    marks.retain('person', people.map((p) => p.id));
    return people;
  }

  @override
  List<Widget> sections(List<Person> data) => [
        FoldSection<Person>(
          storageKey: 'gestion.trabajadores',
          title: 'Trabajadores',
          items: data,
          emptyText: 'No hay personas.',
          builder: (p) => markable('person', p.id, (m, tap, long) => personTile(p, selected: m, line: p.entities.isEmpty ? 'Sin Entidad' : p.entities.join(', '), onTap: tap, onLongPress: long),
              () => openScreen(() => openWorker(context, p.id, person: p))),
        ),
      ];

  @override
  List<ActionItem> actions(List<Person> data) {
    final admin = me.isAdmin;
    if (!marks.active) {
      return [
        if (admin) ActionItem(Icons.person_add_alt_1, 'Registrar trabajador', () => openScreen(() => push(context, const RegisterWorkerForm()))),
        if (me.manages) ActionItem(Icons.qr_code_scanner, 'Incluir por QR', () => openScreen(() => push(context, const IncludeByQrScreen()))),
      ];
    }
    final marked = marks.of('person', data, (p) => p.id);
    return [
      ...markActions(marks, data.map((p) => p.id)),
      if (marks.one) ActionItem(Icons.edit_outlined, 'Abrir', () => openScreen(() => openWorker(context, marked.first.id, person: marked.first))),
      if (admin) ActionItem(Icons.add_business_outlined, 'Asociar Entidad', () => doneWith(() => Ops(context).associateEntity(marked.map((p) => p.id).toList()))),
      if (admin && marks.one) ActionItem(Icons.add_road, 'Añadir itinerario', () => doneWith(() => Ops(context).addItinerary(me, marked.first.id))),
      if (admin && marked.every((p) => !p.isAdmin))
        ActionItem(Icons.delete_outline, 'Eliminar', () => doneWith(() => deleteAll('users', marked.map((p) => p.id), marked.length == 1 ? 'a ${marked.first.fullName}' : 'a ${marked.length} personas',
            'Se elimina la persona con su cuenta, sus pertenencias y sus solicitudes. No afecta a lo demás.', marked.length == 1 ? 'Persona eliminada' : 'Personas eliminadas')), destructive: true),
    ];
  }
}
