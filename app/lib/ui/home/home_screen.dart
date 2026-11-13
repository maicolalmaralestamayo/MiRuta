import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../management/forms.dart';
import '../management/ops.dart';
import '../management/tiles.dart';
import '../navigation.dart';
import '../profile/children_screen.dart';
import '../profile/my_qr_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trip_card.dart';
import '../trips/trip_form_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

/// Lo que muestra Inicio además de la persona (GET me).
class _HomeData {
  final List<Application> applications;
  final TripList trips;
  final List<Child> children;

  const _HomeData(this.applications, this.trips, this.children);
}

/// Inicio (docs/11 §11.60, maqueta G22): prácticamente el formulario del
/// Trabajador de la propia persona: sus datos en una tarjeta, su QR, sus
/// viajes activos, sus Entidades e itinerarios con sus solicitudes, sus
/// paradas y sus hijos. Acciones: ver o editar el perfil, solicitar Entidad
/// o itinerario, cambiar de parada, añadir hijo, declarar ausencia y cerrar
/// sesión.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _view = GlobalKey<DataViewState<_HomeData>>();

  Session get _session => context.read<Session>();

  Future<_HomeData> _load() async {
    final session = _session;
    final api = session.api;
    await session.reloadMe().catchError((_) {});
    final me = session.me!;
    final applications = (await api.getAll('/applications', query: {'filter[mine]': 'true', 'include': 'entity,itinerary,stop,denialReason,resolvedBy'})).map(Application.from).toList();
    final mine = {for (final p in me.placements) p.itineraryId};
    final trips = mine.isEmpty
        ? const TripList([], {})
        : await TripList.load(api, {
            'filter[status]': '${TripStatus.planned},${TripStatus.running}',
            if (mine.length == 1) 'filter[itinerary]': mine.first,
          });
    final children = (await api.getAll('/children', query: {'filter[parent]': me.userId})).map(Child.from).toList();
    // Abrió Inicio: sus solicitudes resueltas quedan vistas.
    if ((session.counters['applicationsResolvedUnseen'] ?? 0) > 0) {
      api.post('/me/applications-seen', const {}).then((_) => session.sync()).catchError((_) {});
    }
    return _HomeData(applications, TripList(trips.trips.where((t) => mine.contains(t.itineraryId)).toList(), trips.ends), children);
  }

  Future<void> _reload() async => _view.currentState?.reload();

  /// Operación que cambia algo: al terminar bien recarga Inicio.
  Future<void> _change(Future<bool> Function() action) async {
    if (await action() && mounted) await _reload();
  }

  Future<void> _open(Future<Object?> Function() opener) async {
    await opener();
    if (mounted) await _reload();
  }

  Future<bool> _changeStop(Me me) async {
    final placements = me.placements;
    if (placements.isEmpty) {
      showMessage(context, 'Aún no tiene itinerario: solicítelo.');
      return false;
    }
    var p = placements.first;
    if (placements.length > 1) {
      final picked = await pickOne<Placement>(context, 'Cambiar de parada en…', placements, (p) => p.itineraryName,
          subtitle: (p) => '${p.entityAbbreviation} • ${p.stopLandmark ?? 'Sin parada'}');
      if (picked == null) return false;
      p = picked;
    }
    if (!mounted) return false;
    return Ops(context).changeStop(p);
  }

  List<ActionItem> _actions() {
    final me = _session.me!;
    final ops = Ops(context);
    return [
      ActionItem(Icons.person_outline, 'Ver o editar el perfil', () => _open(() => push(context, const ProfileScreen()))),
      const ActionItem.divider(),
      ActionItem(Icons.add_business_outlined, 'Solicitar Entidad', () => _change(ops.requestEntity)),
      if (me.hasEntity) ActionItem(Icons.alt_route, 'Solicitar itinerario', () => _change(() => ops.requestItinerary(me))),
      if (me.hasItinerary) ActionItem(Icons.where_to_vote_outlined, 'Cambiar de parada', () => _change(() => _changeStop(me))),
      ActionItem(Icons.person_add_alt_1, 'Añadir hijo', () => _open(() => push(context, const ChildForm()))),
      if (me.hasEntity) ActionItem(Icons.event_busy, 'Declarar ausencia', () => _change(() => ops.declareAbsence(me.memberships))),
      const ActionItem.divider(),
      ActionItem(Icons.logout, 'Cerrar sesión', () async {
        if (await confirm(context, 'Cerrar sesión', '¿Cerrar la sesión en este teléfono?', accept: 'Cerrar sesión', icon: Icons.logout, destructive: true, headerIcon: Icons.logout) &&
            mounted) {
          await _session.logout();
        }
      }, destructive: true),
    ];
  }

  Widget _applications(String title, List<Application> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 16, 2),
        child: Text('$title (${list.length})', style: t.textTheme.titleSmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ),
      for (final a in list) applicationTile(a, mine: true, onTap: () => _change(() => Ops(context).showApplication(a, mine: true, canResolve: false))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    return AppScaffold(
      title: 'Inicio',
      tab: MainTab.home,
      actions: _actions,
      body: DataView<_HomeData>(
        key: _view,
        kinds: const {'applications', 'trips', 'children'},
        cacheKey: 'inicio',
        load: _load,
        fallback: const _HomeData([], TripList([], {}), []),
        builder: (context, data, reload) {
          final placements = me.placements;
          final entityApps = data.applications.where((a) => a.isEntity).toList();
          final itineraryApps = data.applications.where((a) => !a.isEntity).toList();
          final stops = placements.where((p) => p.stopId != null).toList();
          return ListView(
            // Espacio abajo para que la última tarjeta no quede bajo el botón Acciones.
            padding: const EdgeInsets.only(top: 4, bottom: 120),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _PersonHeader(me: me),
              _QrCard(onTap: () => push(context, const MyQrScreen())),
              FoldSection<Trip>(
                storageKey: 'inicio.viajes',
                title: 'Viajes activos',
                items: data.trips.trips,
                emptyText: me.seesTrips ? 'No hay viajes planificados ni en ejecución.' : 'Para ver viajes necesita un itinerario con parada.',
                builder: (t) => TripCard(trip: t, departure: data.trips.departureOf(t), onTap: () => _open(() => push(context, TripFormScreen(tripId: t.id)))),
              ),
              FoldSection<Membership>(
                storageKey: 'inicio.entidades',
                title: 'Entidades',
                items: me.memberships,
                emptyText: 'Aún no tiene Entidad. Use Acciones → Solicitar Entidad.',
                builder: (m) => membershipTile(m, onTap: () => _open(() => openEntity(context, m.entityId))),
              ),
              _applications('Solicitudes de Entidad', entityApps),
              FoldSection<Placement>(
                storageKey: 'inicio.itinerarios',
                title: 'Itinerarios',
                items: placements,
                emptyText: me.hasEntity ? 'Aún no tiene itinerario. Use Acciones → Solicitar itinerario.' : 'Primero solicite entrar en una Entidad.',
                builder: (p) => InfoCard(
                  images: [CardImage(url: p.itineraryImageUrl, icon: Icons.route, dim: !p.itineraryActive)],
                  title: p.itineraryName,
                  lines: [p.entityAbbreviation],
                  chip: p.isChief ? const Chip2('Jefe', green) : null,
                  onTap: () => _open(() => openItinerary(context, p.itineraryId)),
                ),
              ),
              _applications('Solicitudes de itinerario', itineraryApps),
              FoldSection<Placement>(
                storageKey: 'inicio.paradas',
                title: 'Paradas',
                items: stops,
                emptyText: me.hasItinerary ? 'Aún no tiene parada. Use Acciones → Cambiar de parada.' : 'Sin itinerario no hay parada.',
                builder: (p) => InfoCard(
                  images: [CardImage(url: p.stopImageUrl, icon: Icons.place)],
                  title: p.stopLandmark ?? '',
                  lines: [[p.itineraryName, p.stopStreet ?? ''].where((s) => s.isNotEmpty).join(' • ')],
                  onTap: () => _open(() => openStop(context, p.stopId!)),
                ),
              ),
              FoldSection<Child>(
                storageKey: 'inicio.hijos',
                title: 'Hijos',
                items: data.children,
                emptyText: 'No ha declarado hijos.',
                builder: (c) => childTile(c, onTap: () => _open(() => push(context, ChildForm(child: c)))),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Datos de la persona en una tarjeta (maqueta G22): foto, nombre, usuario,
/// carné, sexo y nacimiento, y sus roles.
class _PersonHeader extends StatelessWidget {
  final Me me;

  const _PersonHeader({required this.me});

  Widget _chip(String text, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
      );

  @override
  Widget build(BuildContext context) {
    final roles = [
      if (me.isAdmin) _chip('Administrador', const Color(0xFFFFA000), Colors.black),
      if (me.chiefPlacement != null) _chip('Jefe de ${me.chiefPlacement!.itineraryName}', Colors.white, const Color(0xFF000080)),
      if (me.hasEntity) _chip('Trabajador', Colors.white24, Colors.white),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF000080), Color(0xFF2A2A9E)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 38,
          backgroundColor: Colors.white,
          child: CardImage(url: me.photoUrl, icon: Icons.person, round: true, size: 70),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me.fullName, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(['@${me.username}', if (me.identityCard != null) 'CI ${me.identityCard}'].join(' • '), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (me.sex != null || me.birthDate != null) Text(sexAndBirth(me.sex, me.birthDate), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (roles.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 4, children: roles)],
          ]),
        ),
      ]),
    );
  }
}

/// «Mi QR»: tocarla lo muestra en grande (el QR cambia cada 15 s y la
/// pantalla grande no admite capturas).
class _QrCard extends StatelessWidget {
  final VoidCallback onTap;

  const _QrCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      shape: RoundedRectangleBorder(side: BorderSide(color: t.colorScheme.outline), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.qr_code_2, size: 80, color: Colors.black),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mi QR', style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Cambia solo cada 15 segundos. Tóquelo para verlo en grande.', style: t.textTheme.bodyMedium),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
