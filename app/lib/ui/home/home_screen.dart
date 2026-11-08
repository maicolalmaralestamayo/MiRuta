import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../management/ops.dart';
import '../navigation.dart';
import '../profile/children_screen.dart';
import '../profile/my_qr_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trip_card.dart';
import '../trips/trip_form_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

/// Inicio (docs/11 §11.28, maqueta G18 n.º 3): la persona, los botones
/// Perfil, Hijos y Mi QR; su Entidad, itinerario y parada, su rol y sus
/// viajes; y los avisos «Aún no tiene Entidad / itinerario / parada».
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _entityKey = 'user.home.entity';
  String? _entityId;

  @override
  void initState() {
    super.initState();
    Storage.getString(_entityKey).then((v) {
      if (mounted) setState(() => _entityId = v);
    });
  }

  Future<void> _pickEntity(Me me) async {
    final m = await pickOne<Membership>(context, 'Entidad', me.memberships, (m) => m.entityAbbreviation, subtitle: (m) => m.entityName,
        selected: me.membershipIn(_entityId) ?? me.memberships.first);
    if (m == null) return;
    setState(() => _entityId = m.entityId);
    await Storage.setString(_entityKey, m.entityId);
  }

  Future<void> _request(Future<bool> Function() action) async {
    try {
      if (await action() && mounted) await context.read<Session>().reloadMe();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final m = me.membershipIn(_entityId) ?? me.memberships.firstOrNull;
    final ops = Ops(context);
    return AppScaffold.list(
      title: 'Inicio',
      tab: MainTab.home,
      children: [
        InfoCard(
          images: [CardImage(url: me.photoUrl, icon: Icons.person, round: true)],
          title: me.fullName,
          lines: ['${me.username}${me.identityCard == null ? '' : ' • CI ${me.identityCard}'}'],
          onTap: () => push(context, const ProfileScreen()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            QuickButton(Icons.person_outline, 'Perfil', () => push(context, const ProfileScreen())),
            QuickButton(Icons.child_care, 'Hijos', () => push(context, const ChildrenScreen())),
            QuickButton(Icons.qr_code_2, 'Mi QR', () => push(context, const MyQrScreen())),
          ]),
        ),
        if (!me.hasEntity)
          NoticeCard(
            icon: Icons.apartment,
            title: 'Aún no tiene Entidad',
            detail: 'Solicite entrar en la Entidad donde trabaja. Hasta que la acepten no verá itinerarios ni viajes.',
            buttonIcon: Icons.send,
            buttonText: 'Solicitar Entidad',
            onPressed: () => _request(ops.requestEntity),
          )
        else if (m != null && m.itineraryId == null)
          NoticeCard(
            icon: Icons.route,
            title: 'Aún no tiene itinerario',
            detail: 'Solicite su itinerario en ${m.entityAbbreviation}, o muestre «Mi QR» a su Jefe de itinerario.',
            buttonIcon: Icons.send,
            buttonText: 'Solicitar Itinerario',
            onPressed: () => _request(() => ops.requestItinerary(me)),
          )
        else if (m != null && m.stopId == null)
          NoticeCard(
            icon: Icons.place,
            title: 'Aún no tiene parada',
            detail: 'Elija su parada en ${m.itineraryName}: en Gestión, marque la parada y use «Cambiarme a esta parada».',
            buttonIcon: Icons.where_to_vote_outlined,
            buttonText: 'Elegir parada',
            onPressed: () => MainTabs.go(context, MainTab.management),
          ),
        if (m != null) ...[
          const SectionTitle('Entidad'),
          me.memberships.length > 1
              ? SelectorCard(icon: Icons.apartment, title: m.entityAbbreviation, lines: ['Entidad', m.entityName], onTap: () => _pickEntity(me))
              : InfoCard(images: [CardImage(url: m.entityImageUrl, icon: Icons.apartment)], title: m.entityAbbreviation, lines: ['Entidad', m.entityName]),
          if (m.itineraryId != null) ...[
            const SectionTitle('Itinerario y parada'),
            InfoCard(
              images: const [CardImage(icon: Icons.route), CardImage(icon: Icons.place)],
              title: m.itineraryName ?? '',
              lines: [m.stopLandmark == null ? 'Sin parada' : 'Parada: ${m.stopLandmark}', if (m.stopStreet != null) m.stopStreet!],
              onTap: () => MainTabs.go(context, MainTab.management),
            ),
          ],
        ],
        const SectionTitle('Roles'),
        InfoCard(
          images: const [CardImage(icon: Icons.badge_outlined)],
          title: roleName(me.role),
          lines: [
            switch (me.role) {
              Role.administrador => 'Todas las Entidades',
              Role.jefe => me.chiefMembership == null ? 'Su itinerario' : '${me.chiefMembership!.itineraryName} (${me.chiefMembership!.entityAbbreviation})',
              Role.trabajador => me.memberships.isEmpty ? 'Sin Entidad' : me.memberships.map((m) => m.entityAbbreviation).join(', '),
            },
          ],
        ),
        if (me.seesTrips) ...[
          const SectionTitle('Viajes'),
          SizedBox(
            height: 210,
            child: DataView<TripList>(
              kinds: const {'trips'},
              cacheKey: 'home.trips',
              load: () => TripList.load(context.read<Session>().api, {
                'filter[status]': '${TripStatus.planned},${TripStatus.running}',
                if (m?.itineraryId != null && !me.isAdmin) 'filter[itinerary]': m!.itineraryId,
              }),
              builder: (context, data, reload) {
                final trips = data.trips.take(2).toList();
                if (trips.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(16), child: Text('No hay viajes planificados.'))]);
                return ListView(physics: const NeverScrollableScrollPhysics(), children: [
                  for (final t in trips) TripCard(trip: t, departure: data.departureOf(t), onTap: () => push(context, TripFormScreen(tripId: t.id))),
                ]);
              },
            ),
          ),
        ],
      ],
    );
  }
}
