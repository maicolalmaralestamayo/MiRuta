import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../admin/admin_menu.dart';
import '../navigation.dart';
import '../profile/notices_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/statistics_screen.dart';
import '../../services/app_updates.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    final management = allowedManagementEntries(me);
    return AppScaffold(
      title: 'Más',
      tab: MainTab.more,
      body: ListView(children: [
        UserCard.person(me.person, onTap: () => AppRoutes.profile(context)),
        const Divider(),
        ListTile(leading: const Icon(Icons.qr_code_2), title: const Text('Mi QR'), onTap: () => AppRoutes.myQr(context)),
        if (me.canAnywhere(Op.membersAssignByQr))
          ListTile(leading: const Icon(Icons.qr_code_scanner), title: const Text('Alta en itinerario con QR'), onTap: () => AppRoutes.assignByQr(context)),
        ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Avisos'), onTap: () => open(const NoticesScreen())),
        ListTile(leading: const Icon(Icons.bar_chart), title: const Text('Estadísticas'), onTap: () => open(const StatisticsScreen())),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Ajustes'), onTap: () => open(const SettingsScreen())),
        BusyListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Compartir la app'),
          onTap: () async {
            final arm64 = await pickFrom<bool>(context, '¿Para qué tipo de teléfono?', [true, false],
                (is64) => is64 ? 'La mayoría (64 bits)' : 'Teléfonos antiguos (32 bits)',
                subtitle: (is64) => is64 ? 'Si al instalarla dice que no es compatible, envíe la otra' : 'Solo si la de 64 bits no se instala');
            if (arm64 != null && context.mounted) await AppUpdates.share(context.api, arm64: arm64);
          },
        ),
        // Solo si tiene alguna entrada de Gestión permitida (meta.permissions de GET /me).
        if (management.isNotEmpty) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Gestión'),
            subtitle: Text(me.isAdmin ? 'Administrador' : management.map((e) => e.title).take(3).join(' · ')),
            onTap: () => AppRoutes.management(context),
          ),
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
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: AppVersionText()),
      ]),
    );
  }
}
