import 'package:flutter/material.dart';

import '../settings/global_settings_screen.dart';
import '../widgets/common.dart';
import 'itineraries_screen.dart';
import 'nomenclators_screen.dart';
import 'password_resets_screen.dart';
import 'app_versions_screen.dart';
import 'planning_screen.dart';
import 'stops_screen.dart';
import 'vehicles_screen.dart';
import 'workers_screen.dart';

class AdminMenu extends StatelessWidget {
  const AdminMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión')),
      body: ListView(children: [
        if (me.roles.isItineraryChief) ...[
          const SectionTitle('Mis itinerarios'),
          ListTile(leading: const Icon(Icons.groups), title: const Text('Miembros'), onTap: () => open(WorkersScreen(itineraryIds: me.roles.chiefOfItineraries))),
        ],
        if (me.managesTransport) ...[
          const SectionTitle('Transporte'),
          ListTile(leading: const Icon(Icons.edit_calendar), title: const Text('Planificación de viajes'), onTap: () => open(const PlanningScreen())),
          ListTile(leading: const Icon(Icons.directions_bus), title: const Text('Vehículos y choferes'), onTap: () => open(const VehiclesScreen())),
          ListTile(leading: const Icon(Icons.route), title: const Text('Itinerarios'), onTap: () => open(const ItinerariesScreen())),
          ListTile(leading: const Icon(Icons.place_outlined), title: const Text('Paradas'), onTap: () => open(const StopsScreen())),
          ListTile(leading: const Icon(Icons.people_outline), title: const Text('Trabajadores'), onTap: () => open(const WorkersScreen())),
          ListTile(leading: const Icon(Icons.category_outlined), title: const Text('Tipos de vehículo'), onTap: () => open(NomenclatorsScreen.vehicleTypes())),
          ListTile(leading: const Icon(Icons.event_busy), title: const Text('Tipos de ausencia'), onTap: () => open(NomenclatorsScreen.absenceTypes())),
          ListTile(leading: const Icon(Icons.tune), title: const Text('Ajustes generales'), onTap: () => open(const GlobalSettingsScreen())),
        ],
        if (me.isAdmin) ...[
          const SectionTitle('Administración'),
          ListTile(leading: const Icon(Icons.military_tech_outlined), title: const Text('Jerarquías'), onTap: () => open(NomenclatorsScreen.ranks())),
          ListTile(leading: const Icon(Icons.forum_outlined), title: const Text('Motivos de conversación'), onTap: () => open(NomenclatorsScreen.conversationTopics())),
          ListTile(leading: const Icon(Icons.system_update_alt), title: const Text('Actualizaciones de la app'), onTap: () => open(const AppVersionsScreen())),
          ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Contraseñas olvidadas'), onTap: () => open(const PasswordResetsScreen())),
        ],
      ]),
    );
  }
}
