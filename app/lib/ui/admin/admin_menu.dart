import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../settings/global_settings_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'access_recoveries_screen.dart';
import 'app_versions_screen.dart';
import 'applications_screen.dart';
import 'entities_screen.dart';
import 'itineraries_screen.dart';
import 'itinerary_settings_screen.dart';
import 'nomenclators_screen.dart';
import 'planning_screen.dart';
import 'roles_admin_screen.dart';
import 'server_maintenance_screen.dart';
import 'vehicles_screen.dart';
import 'workers_screen.dart';

/// Una entrada de Gestión: se muestra solo si [allowed] (según los permisos de GET /me).
class ManagementEntry {
  final String section;
  final IconData icon;
  final String title;
  final bool Function(Me me) allowed;
  final Widget Function(BuildContext context) screen;

  const ManagementEntry(this.section, this.icon, this.title, this.allowed, this.screen);
}

bool _any(Me me, List<String> operations) => operations.any(me.canAnywhere);

/// Las entradas de Gestión (docs/11 §11.15 y §11.16). Las pantallas las
/// rehace «gestión» (ver app/V3-APP-BASE.md); aquí solo se decide quién ve cada una.
final List<ManagementEntry> managementEntries = [
  ManagementEntry('Personas', Icons.pending_actions, 'Solicitudes por resolver',
      (me) => _any(me, [Op.entitiesApproveMembership, Op.membersApprove, Op.rolesApprove]), (_) => const ApplicationsToResolveScreen()),
  ManagementEntry('Personas', Icons.people_outline, 'Trabajadores', (me) => _any(me, [Op.workersView, Op.workersRegister]), (_) => const WorkersScreen()),
  ManagementEntry('Transporte', Icons.edit_calendar, 'Planificación de viajes', (me) => me.canAnywhere(Op.tripsPlan), (_) => const PlanningScreen()),
  ManagementEntry('Transporte', Icons.directions_bus, 'Vehículos y choferes', (me) => me.canAnywhere(Op.vehiclesView), (_) => const VehiclesScreen()),
  ManagementEntry('Transporte', Icons.route, 'Itinerarios y paradas',
      (me) => _any(me, [Op.itinerariesView, Op.itinerariesManage, Op.stopsManage]), (_) => const ItinerariesScreen()),
  ManagementEntry('Configuración', Icons.tune, 'Ajustes de la Entidad', (me) => me.canAnywhere(Op.settingsEntity), (_) => const GlobalSettingsScreen.entity()),
  ManagementEntry('Configuración', Icons.alt_route, 'Ajustes por itinerario', (me) => me.canAnywhere(Op.settingsItinerary), (_) => const ItinerarySettingsScreen()),
  ManagementEntry('Configuración', Icons.settings_applications_outlined, 'Ajustes de la app', (me) => me.canAnywhere(Op.settingsApp), (_) => const GlobalSettingsScreen.app()),
  ManagementEntry('Administración', Icons.apartment_outlined, 'Entidades', (me) => _any(me, [Op.entitiesView, Op.entitiesManage]), (_) => const EntitiesScreen()),
  ManagementEntry('Administración', Icons.admin_panel_settings_outlined, 'Roles', (me) => _any(me, [Op.rolesView, Op.rolesManage]), (_) => const RolesAdminScreen()),
  ManagementEntry('Administración', Icons.lock_reset, 'Olvidé algo', (me) => me.canAnywhere(Op.accessRecoveriesManage), (_) => const AccessRecoveriesScreen()),
  ManagementEntry('Administración', Icons.category_outlined, 'Tipos de vehículo', (me) => me.canAnywhere(Op.nomenclatorsManage), (_) => NomenclatorsScreen.vehicleTypes()),
  ManagementEntry('Administración', Icons.forum_outlined, 'Motivos de conversación', (me) => me.canAnywhere(Op.nomenclatorsManage), (_) => NomenclatorsScreen.conversationTopics()),
  ManagementEntry('Administración', Icons.event_busy, 'Tipos de ausencia', (me) => me.canAnywhere(Op.absenceTypesManage), (_) => NomenclatorsScreen.absenceTypes()),
  ManagementEntry('Administración', Icons.system_update_alt, 'Actualizaciones de la app', (me) => me.canAnywhere(Op.appVersionsManage), (_) => const AppVersionsScreen()),
  ManagementEntry('Administración', Icons.dns_outlined, 'Mantenimiento del servidor', (me) => me.canAnywhere(Op.maintenanceRun),
      (context) => ServerMaintenanceScreen(api: context.api)),
];

/// Las entradas que puede ver esa persona.
List<ManagementEntry> allowedManagementEntries(Me me) => managementEntries.where((e) => e.allowed(me)).toList();

/// Gestión (Más → Gestión): solo las entradas permitidas.
class AdminMenu extends StatefulWidget {
  const AdminMenu({super.key});

  @override
  State<AdminMenu> createState() => _AdminMenuState();
}

class _AdminMenuState extends State<AdminMenu> {
  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final entries = allowedManagementEntries(me);
    final sections = <String>{for (final e in entries) e.section};
    return AppScaffold.list(title: 'Gestión', tab: MainTab.more, children: [
      // Entidad con la que se trabaja en las pantallas de gestión antiguas
      // (Session.adminEntity / context.entityFilter).
      if (me.isAdmin) AdminEntitySelector(onChanged: () => setState(() {})),
      for (final section in sections) ...[
        SectionTitle(section),
        for (final entry in entries.where((e) => e.section == section))
          ListTile(
            leading: Icon(entry.icon),
            title: Text(entry.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: entry.screen)),
          ),
      ],
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No tiene tareas de gestión.')),
    ]);
  }
}
