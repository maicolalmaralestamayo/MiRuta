import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../admin/admin_menu.dart';
import '../profile/children_screen.dart';
import '../profile/notices_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/statistics_screen.dart';
import '../../services/app_updates.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    final hasStatistics = true;
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(children: [
        ListTile(
          leading: WorkerAvatar.of(photoUrl: me.photoUrl, name: me.name),
          title: Text(me.fullName),
          subtitle: RankBadge(me.rank),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => open(const ProfileScreen()),
        ),
        const Divider(),
        if (me.hasWorker) ListTile(leading: const Icon(Icons.child_care), title: const Text('Mis hijos'), onTap: () => open(const ChildrenScreen())),
        ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Avisos'), onTap: () => open(const NoticesScreen())),
        if (hasStatistics) ListTile(leading: const Icon(Icons.bar_chart), title: const Text('Estadísticas'), onTap: () => open(const StatisticsScreen())),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Ajustes'), onTap: () => open(const SettingsScreen())),
        BusyListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Compartir la app'),
          subtitle: const Text('Envíala a un compañero por WhatsApp, Bluetooth, Quick Share…'),
          onTap: () async {
            final arm64 = await pickFrom<bool>(context, '¿Para qué tipo de teléfono?', [true, false],
                (is64) => is64 ? 'La mayoría (64 bits)' : 'Teléfonos antiguos (32 bits)',
                subtitle: (is64) => is64 ? 'Si al instalarla dice que no es compatible, envía la otra' : 'Solo si la de 64 bits no se instala');
            if (arm64 != null && context.mounted) await AppUpdates.share(context.api, arm64: arm64);
          },
        ),
        if (me.managesTransport || me.roles.isItineraryChief) ...[
          const Divider(),
          ListTile(leading: const Icon(Icons.manage_accounts_outlined), title: const Text('Gestión'), subtitle: Text(_roles(context)), onTap: () => open(const AdminMenu())),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: () async {
            final everywhere = await pickFrom<bool>(context, 'Cerrar sesión', [false, true], (all) => all ? 'En todos mis dispositivos' : 'Solo en este teléfono');
            if (everywhere != null && context.mounted) await context.session.logout(everywhere: everywhere);
          },
        ),
      ]),
    );
  }

  String _roles(BuildContext context) {
    final me = context.me;
    return [
      if (me.isAdmin) 'Administrador',
      if (me.roles.isTransportChief) 'Jefe de Transporte',
      if (me.roles.isItineraryChief) 'Jefe de itinerario',
    ].join(' · ');
  }
}
