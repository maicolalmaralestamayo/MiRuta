import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:provider/provider.dart';

import '../../services/app_info.dart';
import '../../services/app_updates.dart';
import '../../services/session.dart';
import '../admin/access_recoveries_screen.dart';
import '../admin/app_versions_screen.dart';
import '../admin/maintenance_screen.dart';
import '../admin/settings_screen.dart';
import '../chat/conversations_screen.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Más (docs/11 §11.38 y §11.60): Conversaciones, Compartir la app y las
/// herramientas del Administrador. Mi QR, el perfil y Cerrar sesión están en
/// Inicio; los nomencladores, en Gestión.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _version = '';
  AppUpdate? _update;
  String? _progress;

  @override
  void initState() {
    super.initState();
    AppInfo.label().then((v) {
      if (mounted) setState(() => _version = v);
    });
    AppUpdates.check(context.read<Session>().api).then((u) {
      if (mounted) setState(() => _update = u);
    }).catchError((_) {});
  }

  Future<void> _share() async {
    final arm64 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.share_outlined, size: 32),
        title: const Text('Compartir la app', textAlign: TextAlign.center),
        content: const Text('¿Para qué tipo de teléfono? La mayoría de los teléfonos actuales son de 64 bits.', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          cancelButton(context),
          TextButton.icon(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.phone_android), label: const Text('32 bits')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.phone_android), label: const Text('64 bits')),
        ],
      ),
    );
    if (arm64 == null || !mounted) return;
    await runAction(context, () => AppUpdates.share(context.read<Session>().api, arm64: arm64));
  }

  void _install(AppUpdate update) {
    if (update.downloadUrl == null) return;
    setState(() => _progress = 'Descargando…');
    AppUpdates.install(update).listen((event) {
      if (!mounted) return;
      setState(() => _progress = switch (event.status) {
            OtaStatus.DOWNLOADING => 'Descargando ${event.value ?? ''} %',
            OtaStatus.INSTALLING || OtaStatus.INSTALLATION_DONE => 'Abriendo el instalador…',
            _ => 'No se pudo descargar la actualización.',
          });
    }, onError: (Object _) {
      if (mounted) setState(() => _progress = 'No se pudo descargar la actualización.');
    });
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap, [String? subtitle]) =>
      ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me!;
    final update = _update;
    return AppScaffold.list(
      title: 'Más',
      tab: MainTab.more,
      children: [
        if (update != null)
          NoticeCard(
            icon: Icons.system_update,
            title: 'Actualización disponible',
            detail: 'Versión ${update.versionName}${update.sizeBytes > 0 ? ' (${update.sizeLabel})' : ''}.${update.notes == null ? '' : ' ${update.notes}'}${_progress == null ? '' : '\n$_progress'}',
            buttonIcon: Icons.download,
            buttonText: 'Descargar e instalar',
            onPressed: () => _install(update),
            color: blue2,
          ),
        const SectionTitle('Para mí'),
        _tile(Icons.forum_outlined, 'Conversaciones', () => push(context, const ConversationsScreen()), me.isAdmin ? 'Mensajes al desarrollador' : 'Escribir al desarrollador'),
        _tile(Icons.share_outlined, 'Compartir la app', _share),
        if (me.isAdmin) ...[
          const SectionTitle('Administrador'),
          _tile(Icons.settings_applications_outlined, 'Ajustes de la app', () => push(context, const SettingsScreen())),
          _tile(Icons.lock_reset, 'Olvidé algo', () => push(context, const AccessRecoveriesScreen()), 'Solicitudes de recuperación de acceso'),
          _tile(Icons.system_update_alt, 'Actualizaciones de la app', () => push(context, const AppVersionsScreen())),
          _tile(Icons.dns_outlined, 'Mantenimiento del servidor', () => push(context, const MaintenanceScreen())),
        ],
        const Divider(),
        Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(_version, style: const TextStyle(color: grey)))),
      ],
    );
  }
}
