import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api/children_api.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../navigation.dart';
import '../profile/notices_screen.dart';
import '../trips/trip_card.dart';
import '../trips/trip_context.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';

/// Inicio (docs/11 §11.10; maqueta inicio-propuesta-3.png), de arriba abajo:
/// tarjeta del usuario, los seis botones, Hijos (con derecho), Entidad
/// (selector), Itinerario y parada, Roles (Trabajador primero) y Viajes de
/// la Entidad elegida. Al tocar cada tarjeta se abre su pantalla.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me!;
    final membership = session.selectedMembership;
    return AppScaffold(
      title: 'Inicio',
      appBarActions: [
        IconButton(
          tooltip: 'Avisos',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen())),
        ),
      ],
      body: AsyncView<_HomeData>(
        // Se recarga al elegir otra Entidad o al cambiar sus datos.
        key: ValueKey('${membership?.entityId}-${membership?.itineraryId}-${me.memberships.length}'),
        load: () => _HomeData.load(context, me, membership),
        builder: (context, data, reload) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), children: [
          UserCard.person(me.person, onTap: () => AppRoutes.profile(context)),
          const HomeButtons(),
          if (data.children.isNotEmpty) ...[
            const SectionHeader('Hijos'),
            for (final child in data.children)
              ChildCard(child, onTap: () async {
                await AppRoutes.childForm(context, child);
                reload();
              }),
          ],
          const SectionHeader('Entidad'),
          const EntitySelector(),
          if (membership != null) ...[
            const SectionHeader('Itinerario y parada'),
            ItineraryStopCard.membership(membership, onTap: () => AppRoutes.itinerary(context)),
            const SectionHeader('Roles'),
            RoleCard.worker(membership.entity, onTap: () => AppRoutes.roles(context)),
            for (final role in membership.extraRoles) RoleCard.held(role, membership.entity, onTap: () => AppRoutes.roles(context)),
            if (data.trips.isNotEmpty) ...[
              const SectionHeader('Viajes'),
              for (final trip in data.trips)
                TripCard(
                  trip: trip,
                  legs: data.legs[trip.id],
                  showOverload: me.can(Op.tripsEdit, entityId: trip.entityId, itineraryId: trip.itineraryId),
                  onTap: () async {
                    await AppRoutes.tripDetail(context, trip.id);
                    reload();
                  },
                ),
            ],
          ],
          // El Administrador sin Entidad puede entrar en una sin solicitud (docs/11 §11.13).
          if (me.isAdmin && !me.hasEntity)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.tonalIcon(onPressed: () => joinEntityAsAdmin(context), icon: const Icon(Icons.add_business_outlined), label: const Text('Unirme a una Entidad')),
            ),
        ]),
      ),
    );
  }
}

class _HomeData {
  final List<Child> children;
  final List<Trip> trips;
  final Map<String, List<TripLeg>> legs;

  _HomeData(this.children, this.trips, this.legs);

  /// Hijos con derecho (de la persona, sea cual sea la Entidad) y los viajes
  /// en curso y confirmados de la Entidad elegida en los que viaja o conduce.
  static Future<_HomeData> load(BuildContext context, Me me, Membership? membership) async {
    final api = context.api;
    final children = (await ChildrenApi(api).mine(me.id, eligible: true, active: true)).where((c) => c.travels).toList();
    if (membership == null) return _HomeData(children, const [], const {});
    final now = DateTime.now();
    final trips = (await api.get('/trips', query: {
      'include': SyncService.tripInclude,
      'filter[status]': TripStatus.confirmed,
      'filter[from]': now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10),
      'sort': 'departsAt',
      'page[size]': 30,
    }))
        .resources
        .map(Trip.from)
        .where((trip) =>
            trip.returnsAt.isAfter(now) &&
            (trip.entityId == null || trip.entityId == membership.entityId) &&
            (trip.itineraryId == membership.itineraryId || trip.driverId == membership.workerId))
        .take(10)
        .toList();
    final legs = await TripContext.legsOf(api, trips);
    // En curso primero (docs/11 §11.10: «tarjeta de viaje actual»).
    bool running(Trip trip) => (legs[trip.id] ?? const []).any((leg) => leg.isActive);
    trips.sort((a, b) => running(a) == running(b) ? a.departsAt.compareTo(b.departsAt) : (running(a) ? -1 : 1));
    return _HomeData(children, trips, legs);
  }
}

/// Los seis botones de Inicio (docs/11 §11.10 y §11.18): ícono y una palabra,
/// 3 por fila, centrados y del mismo tamaño.
class HomeButtons extends StatelessWidget {
  const HomeButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final buttons = <(IconData, String, VoidCallback)>[
      (Icons.person_outline, 'Perfil', () => AppRoutes.profile(context)),
      (Icons.child_care, 'Hijos', () => AppRoutes.children(context)),
      (Icons.apartment, 'Entidades', () => AppRoutes.entities(context)),
      (Icons.route, 'Itinerario', () => AppRoutes.itinerary(context)),
      (Icons.badge_outlined, 'Roles', () => AppRoutes.roles(context)),
      (Icons.directions_bus, 'Viajes', () => AppRoutes.trips(context)),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 8.0;
      const padding = 12.0;
      final width = ((constraints.maxWidth - 2 * padding - 2 * spacing) / 3).clamp(80.0, 140.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(padding, 8, padding, 0),
        child: Wrap(alignment: WrapAlignment.center, spacing: spacing, runSpacing: spacing, children: [
          for (final (icon, label, onTap) in buttons) QuickButton(icon: icon, label: label, width: width, onTap: onTap),
        ]),
      );
    });
  }
}

/// Botón cuadrado con ícono y una palabra debajo.
class QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final double width;
  final VoidCallback onTap;

  const QuickButton({super.key, required this.icon, required this.label, required this.onTap, this.width = 120});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: width,
      height: 72,
      child: Material(
        color: t.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 26, color: t.colorScheme.onSecondaryContainer),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge!.copyWith(color: t.colorScheme.onSecondaryContainer)),
          ]),
        ),
      ),
    );
  }
}
