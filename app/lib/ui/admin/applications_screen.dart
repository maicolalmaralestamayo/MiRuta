import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';

/// Una solicitud por resolver con lo que trae incluido.
class ApplicationItem {
  final Application application;
  final Entity? entity;
  final String? itineraryImageUrl;
  final String? stopStreet;
  final String? stopImageUrl;
  final String? roleIcon;

  const ApplicationItem(this.application, {this.entity, this.itineraryImageUrl, this.stopStreet, this.stopImageUrl, this.roleIcon});

  factory ApplicationItem.from(Resource r) {
    final entity = r.related('entity');
    return ApplicationItem(
      Application.from(r),
      entity: entity == null ? null : Entity.from(entity),
      itineraryImageUrl: r.related('itinerary')?.string('imageUrl'),
      stopStreet: r.related('stop')?.string('street'),
      stopImageUrl: r.related('stop')?.string('imageUrl'),
      roleIcon: r.related('role')?.string('icon'),
    );
  }

  String get id => application.id;

  String get applicantName => application.applicant?.fullName ?? application.applicantName ?? '';

  /// Qué pide, en una línea: «Entrar en UMIM», «Ruta Playa • Coppelia (UMIM)», «Chofer en UMIM».
  String get what {
    final a = application;
    final abbreviation = a.entityAbbreviation ?? entity?.abbreviation ?? '';
    return switch (a.type) {
      ApplicationType.entityMembership => 'Entrar en $abbreviation',
      ApplicationType.itineraryMembership => '${a.subject} ($abbreviation)',
      _ => '${a.roleName ?? 'Rol'}${a.itineraryName == null ? '' : ' de ${a.itineraryName}'} en $abbreviation',
    };
  }
}

/// Aprueba o rechaza solicitudes (el motivo es obligatorio al rechazar).
/// Devuelve true si se resolvió alguna.
Future<bool> resolveApplications(BuildContext context, List<Application> applications, {required bool approve}) async {
  String? note;
  if (approve) {
    final ok = await confirm(context, 'Aprobar',
        applications.length == 1 ? '¿Aprobar la solicitud de ${applications.first.applicantName ?? 'esta persona'}?' : '¿Aprobar ${plural(applications.length, 'solicitud', 'solicitudes')}?',
        accept: 'Aprobar');
    if (!ok) return false;
  } else {
    note = await promptText(context, 'Motivo del rechazo', label: 'Motivo (obligatorio)', required: true, maxLines: 3);
    if (note == null || note.isEmpty) return false;
  }
  if (!context.mounted) return false;
  final api = MembershipsApi(context.api);
  return runAction(context, () async {
    for (final a in applications) {
      await api.resolveApplication(a.id, approve: approve, note: note);
    }
  }, success: approve ? (applications.length == 1 ? 'Solicitud aprobada.' : 'Solicitudes aprobadas.') : (applications.length == 1 ? 'Solicitud rechazada.' : 'Solicitudes rechazadas.'));
}

/// Solicitudes por resolver (Gestión): entrada en una Entidad, itinerario y
/// parada, y roles que la persona puede aprobar o rechazar. Se agrupan por
/// tipo; cada tarjeta dice quién pide qué y en qué Entidad.
class ApplicationsToResolveScreen extends StatefulWidget {
  const ApplicationsToResolveScreen({super.key});

  @override
  State<ApplicationsToResolveScreen> createState() => _ApplicationsToResolveScreenState();
}

class _ApplicationsToResolveScreenState extends State<ApplicationsToResolveScreen> {
  final _view = GlobalKey<AsyncViewState<List<ApplicationItem>>>();
  final _selection = SelectionController();
  List<ApplicationItem> _items = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<ApplicationItem>> _load() async {
    final items = (await context.api.getAll('/applications', query: {
      'filter[toResolve]': 'true',
      'filter[status]': ApplicationStatus.pending,
      'include': 'user,entity,itinerary,stop,role',
      'sort': 'createdAt',
    }))
        .map(ApplicationItem.from)
        .where((i) => i.application.canResolve && i.application.isPending)
        .toList();
    _items = items;
    _selection.retain(items.map((i) => i.id));
    return items;
  }

  List<Application> get _selected => _selection.selectedOf(_items, (i) => i.id).map((i) => i.application).toList();

  Future<void> _resolve(bool approve) async {
    if (await resolveApplications(context, _selected, approve: approve)) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  Future<void> _open(ApplicationItem item) async {
    final resolved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ApplicationDetailScreen(item: item)));
    if (resolved == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Solicitudes por resolver',
      tab: MainTab.more,
      selection: _selection,
      selectionTitle: (n) => n == 1 ? '1 seleccionada' : '$n seleccionadas',
      actions: [
        ActionItem(icon: Icons.check_circle_outline, label: 'Aprobar', needs: ActionNeeds.some, onPressed: () => _resolve(true)),
        ActionItem(icon: Icons.cancel_outlined, label: 'Rechazar', needs: ActionNeeds.some, destructive: true, onPressed: () => _resolve(false)),
      ],
      body: AsyncView<List<ApplicationItem>>(
        key: _view,
        load: _load,
        builder: (context, items, reload) {
          List<ApplicationItem> of(String type) => items.where((i) => i.application.type == type).toList();
          return SelectableCardList<ApplicationItem>(
            controller: _selection,
            sections: [
              CardSection(title: 'Entrar en una Entidad', items: of(ApplicationType.entityMembership)),
              CardSection(title: 'Itinerario y parada', items: of(ApplicationType.itineraryMembership)),
              CardSection(title: 'Roles', items: of(ApplicationType.role)),
            ],
            emptyText: 'No hay solicitudes por resolver.',
            keyOf: (i) => i.id,
            onOpen: _open,
            cardBuilder: (context, i, selected, onTap, onLongPress) => InfoCard(
              images: [CardImage(url: i.application.applicant?.photoUrl, icon: Icons.person, round: true)],
              title: i.applicantName,
              lines: [i.what, requestedOn(i.application.createdAt)],
              chip: CardChip(ApplicationStatus.label(ApplicationStatus.pending), color: applicationStatusColor(ApplicationStatus.pending)),
              selected: selected,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
          );
        },
      ),
    );
  }
}

/// Una solicitud: quién la pide (con su carné si se puede ver) y qué pide.
/// Acciones: Aprobar y Rechazar (con motivo).
class ApplicationDetailScreen extends StatelessWidget {
  final ApplicationItem item;

  const ApplicationDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final a = item.application;
    final person = a.applicant;
    Future<void> resolve(bool approve) async {
      if (await resolveApplications(context, [a], approve: approve) && context.mounted) Navigator.pop(context, true);
    }

    return AppScaffold(
      title: 'Solicitud',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.check_circle_outline, label: 'Aprobar', enabled: a.canResolve, onPressed: () => resolve(true)),
        ActionItem(icon: Icons.cancel_outlined, label: 'Rechazar', enabled: a.canResolve, destructive: true, onPressed: () => resolve(false)),
      ],
      body: ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: [
        const SectionHeader('Quién la pide'),
        if (person != null) UserCard.person(person) else UserCard(fullName: item.applicantName),
        if (person?.identityCard != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ReadOnlyField(label: 'Carné de identidad', value: person!.identityCard!, icon: Icons.badge_outlined),
          ),
        SectionHeader(ApplicationType.label(a.type)),
        switch (a.type) {
          ApplicationType.entityMembership => EntityCard(item.entity, extraLine: requestedOn(a.createdAt)),
          ApplicationType.itineraryMembership => ItineraryStopCard(
              itineraryName: a.itineraryName,
              itineraryImageUrl: item.itineraryImageUrl,
              street: item.stopStreet,
              landmark: a.stopLandmark,
              stopImageUrl: item.stopImageUrl,
              extraLine: '${a.entityAbbreviation ?? ''} • ${requestedOn(a.createdAt)}',
            ),
          _ => RoleCard(
              name: a.roleName ?? 'Rol',
              icon: item.roleIcon,
              subtitle: a.itineraryName ?? a.entityAbbreviation ?? '',
              extraLine: requestedOn(a.createdAt),
            ),
        },
      ]),
    );
  }
}
