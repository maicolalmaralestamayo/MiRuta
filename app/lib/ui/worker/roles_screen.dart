import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/api/roles_api.dart';
import '../../services/session.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/entity_selector.dart';
import '../widgets/selection.dart';
import 'worker_common.dart';

/// Roles (docs/11 §11.16 y §11.18; maqueta pantallas-final.png, 6). Con
/// selector de Entidad: «Mis roles» (siempre primero «Trabajador», que no se
/// solicita ni se deja) y «Solicitudes pendientes».
///
/// Acciones: Solicitar un rol (solo los que se pueden solicitar; si es por
/// itinerario, se elige el itinerario), Darme de baja y Cancelar solicitud.
class MyRolesScreen extends StatefulWidget {
  const MyRolesScreen({super.key});

  @override
  State<MyRolesScreen> createState() => _MyRolesScreenState();
}

typedef _Data = ({List<Application> applications, List<Role> roles});

class _MyRolesScreenState extends State<MyRolesScreen> {
  static const _worker = 'worker';
  static const _role = 'role:';
  static const _application = 'application:';

  final _selection = SelectionController();
  final _views = <String, GlobalKey<AsyncViewState<_Data>>>{};
  String _viewKey = '';
  List<Role> _roles = const [];
  List<Application> _applications = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<_Data> _load(Membership? membership) async {
    if (membership == null) return (applications: const <Application>[], roles: const <Role>[]);
    final applications = MembershipsApi(context.api).myApplications(type: ApplicationType.role, entityId: membership.entityId);
    final roles = RolesApi(context.api).all();
    final data = (applications: await applications, roles: await roles);
    _roles = data.roles;
    _applications = data.applications;
    return data;
  }

  Future<void> _reload() async {
    _selection.clear();
    await _views[_viewKey]?.currentState?.reload();
  }

  Future<void> _request(Membership membership) async {
    final held = {for (final r in membership.roles) r.roleId};
    final pending = {for (final a in _applications) a.roleId};
    final roles = _roles.where((r) => r.requestable && !r.isAdministrator && !held.contains(r.id) && !pending.contains(r.id)).toList();
    if (roles.isEmpty) {
      showMessage(context, 'No hay roles que pueda solicitar en ${membership.entity.abbreviation}.');
      return;
    }
    final role = await pickFrom<Role>(context, 'Solicitar un rol en ${membership.entity.abbreviation}', roles, (r) => r.name,
        subtitle: (r) => r.itineraryScoped ? 'De un itinerario' : membership.entity.abbreviation);
    if (role == null || !mounted) return;
    Itinerary? itinerary;
    if (role.itineraryScoped) {
      final itineraries = await MembershipsApi(context.api).itineraries(membership.entityId);
      if (!mounted) return;
      if (itineraries.isEmpty) {
        showMessage(context, '${membership.entity.abbreviation} todavía no tiene itinerarios.');
        return;
      }
      itinerary = await pickFrom<Itinerary>(context, '${role.name}: elija el itinerario', itineraries, (i) => i.name);
      if (itinerary == null || !mounted) return;
    }
    final ok = await confirm(context, 'Solicitar un rol',
        '¿Solicitar el rol ${role.name}${itinerary == null ? '' : ' de ${itinerary.name}'} en ${membership.entity.abbreviation}?',
        accept: 'Solicitar');
    if (!ok || !mounted) return;
    await MembershipsApi(context.api).requestRole(roleId: role.id, entityId: membership.entityId, itineraryId: itinerary?.id);
    if (!mounted) return;
    showMessage(context, 'Solicitud enviada. Le avisaremos cuando la resuelvan.');
    await _reload();
  }

  Future<void> _resign() async {
    final session = context.session;
    final api = RolesApi(session.api);
    for (final id in SelectionKeys.ids(_selection, _role)) {
      await api.remove(id);
    }
    await session.reloadMe();
    if (!mounted) return;
    showMessage(context, 'Se dio de baja del rol.');
    await _reload();
  }

  Future<void> _cancel() async {
    final api = MembershipsApi(context.api);
    for (final id in SelectionKeys.ids(_selection, _application)) {
      await api.cancelApplication(id);
    }
    if (!mounted) return;
    showMessage(context, 'Solicitud cancelada');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final membership = context.watch<Session>().selectedMembership;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => AppScaffold(
        title: 'Roles',
        selection: _selection,
        actions: [
          ActionItem(icon: Icons.add_moderator_outlined, label: 'Solicitar un rol', enabled: membership != null, onPressed: () => _request(membership!)),
          const ActionItem.divider(),
          ActionItem(
            icon: Icons.logout,
            label: 'Darme de baja',
            needs: ActionNeeds.some,
            enabled: SelectionKeys.allAre(_selection, _role),
            confirmation: '¿Darse de baja de los roles seleccionados? Para volver a tenerlos tendrá que solicitarlos de nuevo.',
            onPressed: _resign,
          ),
          ActionItem(
            icon: Icons.cancel_outlined,
            label: 'Cancelar solicitud',
            needs: ActionNeeds.some,
            enabled: SelectionKeys.allAre(_selection, _application),
            confirmation: '¿Cancelar las solicitudes seleccionadas?',
            onPressed: _cancel,
          ),
        ],
        body: AsyncView<_Data>(
          key: _views.putIfAbsent(_viewKey = '${membership?.workerId}-${membership?.roles.length}', GlobalKey.new),
          load: () => _load(membership),
          builder: (context, data, reload) {
            final header = [EntitySelector(onChanged: (_) => _selection.clear())];
            if (membership == null) {
              return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: [
                ...header,
                const Padding(padding: EdgeInsets.all(24), child: Text('Cuando le aprueben la entrada en una Entidad podrá solicitar roles en ella.', textAlign: TextAlign.center)),
                const DeveloperChatFooter(),
              ]);
            }
            final icons = {for (final r in data.roles) r.id: r.icon};
            final mine = <Object>[_worker, ...membership.extraRoles];
            String keyOf(Object item) => switch (item) {
                  HeldRole r => '$_role${r.id}',
                  Application a => '$_application${a.id}',
                  _ => _worker,
                };
            return ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
              SelectableCardList<Object>(
                controller: _selection,
                scrollable: false,
                header: header,
                sections: [
                  CardSection(title: 'Mis roles', items: mine),
                  CardSection(title: 'Solicitudes pendientes', items: data.applications),
                ],
                keyOf: keyOf,
                // «Trabajador» no se deja: no se puede seleccionar.
                canSelect: (item) => item != _worker,
                cardBuilder: (context, item, selected, onTap, onLongPress) => switch (item) {
                  HeldRole r => RoleCard.held(r, membership.entity, selected: selected, onTap: onTap, onLongPress: onLongPress),
                  Application a => RoleCard(
                      name: a.roleName ?? '',
                      subtitle: a.itineraryName ?? a.entityAbbreviation ?? membership.entity.abbreviation,
                      icon: icons[a.roleId],
                      chip: pendingChip(),
                      extraLine: requestedOn(a),
                      selected: selected,
                      onTap: onTap,
                      onLongPress: onLongPress,
                    ),
                  _ => RoleCard.worker(membership.entity, onTap: onTap),
                },
              ),
              const DeveloperChatFooter(),
            ]);
          },
        ),
      ),
    );
  }
}
