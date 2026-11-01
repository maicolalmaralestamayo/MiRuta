import 'package:flutter/material.dart';

import '../settings/global_settings_screen.dart';
import '../widgets/common.dart';
import 'itineraries_screen.dart';
import 'nomenclators_screen.dart';
import 'access_recoveries_screen.dart';
import 'entities_screen.dart';
import 'app_versions_screen.dart';
import 'planning_screen.dart';
import 'vehicles_screen.dart';
import 'workers_screen.dart';

class AdminMenu extends StatefulWidget {
  const AdminMenu({super.key});

  @override
  State<AdminMenu> createState() => _AdminMenuState();
}

class _AdminMenuState extends State<AdminMenu> {
  @override
  Widget build(BuildContext context) {
    final me = context.me;
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión')),
      body: ListView(children: [
        if (me.isAdmin) AdminEntitySelector(onChanged: () => setState(() {})),
        if (me.roles.isItineraryChief && !me.managesTransport) ...[
          const SectionTitle('Mi itinerario'),
          ListTile(leading: const Icon(Icons.edit_calendar), title: const Text('Planificación de viajes'), onTap: () => open(const PlanningScreen())),
          ListTile(leading: const Icon(Icons.groups), title: const Text('Miembros y trabajadores sin teléfono'), onTap: () => open(WorkersScreen(itineraryIds: me.roles.chiefOfItineraries))),
        ],
        if (me.managesTransport) ...[
          const SectionTitle('Transporte'),
          ListTile(leading: const Icon(Icons.edit_calendar), title: const Text('Planificación de viajes'), onTap: () => open(const PlanningScreen())),
          ListTile(leading: const Icon(Icons.directions_bus), title: const Text('Vehículos y choferes'), onTap: () => open(const VehiclesScreen())),
          ListTile(leading: const Icon(Icons.route), title: const Text('Itinerarios y paradas'), onTap: () => open(const ItinerariesScreen())),
          ListTile(leading: const Icon(Icons.people_outline), title: const Text('Trabajadores'), onTap: () => open(const WorkersScreen())),
          ListTile(leading: const Icon(Icons.tune), title: const Text('Ajustes de la Entidad'), onTap: () => open(const GlobalSettingsScreen.entity())),
        ],
        if (me.isAdmin) ...[
          const SectionTitle('Administración'),
          ListTile(leading: const Icon(Icons.apartment_outlined), title: const Text('Entidades'), onTap: () => open(const EntitiesScreen())),
          ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Olvidé algo'), onTap: () => open(const AccessRecoveriesScreen())),
          ListTile(leading: const Icon(Icons.settings_applications_outlined), title: const Text('Ajustes de la app'), onTap: () => open(const GlobalSettingsScreen.app())),
          ListTile(leading: const Icon(Icons.category_outlined), title: const Text('Tipos de vehículo'), onTap: () => open(NomenclatorsScreen.vehicleTypes())),
          ListTile(leading: const Icon(Icons.event_busy), title: const Text('Tipos de ausencia'), onTap: () => open(NomenclatorsScreen.absenceTypes())),
          ListTile(leading: const Icon(rankIcon), title: const Text('Jerarquías'), onTap: () => open(NomenclatorsScreen.ranks())),
          ListTile(leading: const Icon(Icons.forum_outlined), title: const Text('Motivos de conversación'), onTap: () => open(NomenclatorsScreen.conversationTopics())),
          ListTile(leading: const Icon(Icons.system_update_alt), title: const Text('Actualizaciones de la app'), onTap: () => open(const AppVersionsScreen())),
        ],
      ]),
    );
  }
}
