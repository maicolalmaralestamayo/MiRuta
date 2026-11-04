import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';

/// «Olvidé algo» (solo el Administrador, docs/11 §11.7): la persona pidió su
/// usuario, su contraseña o ambos con su carné y un teléfono. Tras
/// confirmarlo por una tercera vía (llamada o WhatsApp) se aprueba o se
/// rechaza. Al aprobar se comunica solo lo pedido; la contraseña nueva la
/// propone el sistema y se muestra aquí una vez.
class AccessRecoveriesScreen extends StatefulWidget {
  const AccessRecoveriesScreen({super.key});

  @override
  State<AccessRecoveriesScreen> createState() => _AccessRecoveriesScreenState();
}

String _what(Resource r) {
  final user = r.boolean('forgotUsername');
  final password = r.boolean('forgotPassword');
  return user && password ? 'Olvidó el usuario y la contraseña' : (user ? 'Olvidó el usuario' : 'Olvidó la contraseña');
}

class _AccessRecoveriesScreenState extends State<AccessRecoveriesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Resource>>>();
  final _selection = SelectionController();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<Resource>> _load() async => (await context.api.get('/access-recoveries', query: {'include': 'user,installation', 'page[size]': 100})).resources;

  Future<void> _open(Resource recovery) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AccessRecoveryScreen(recovery: recovery)));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Olvidé algo',
      tab: MainTab.more,
      body: AsyncView<List<Resource>>(
        key: _view,
        load: _load,
        builder: (context, recoveries, reload) => SelectableCardList<Resource>(
          controller: _selection,
          sections: [
            CardSection(title: 'Pendientes', items: recoveries.where((r) => r.string('status') == 'pending').toList()),
            CardSection(title: 'Aprobadas (aún no vistas en el teléfono)', items: recoveries.where((r) => r.string('status') == 'approved').toList()),
          ],
          emptyText: 'No hay solicitudes abiertas.',
          keyOf: (r) => r.id,
          canSelect: (_) => false,
          onOpen: _open,
          cardBuilder: (context, r, selected, onTap, onLongPress) {
            final user = r.related('user');
            final pending = r.string('status') == 'pending';
            return InfoCard(
              images: [CardImage(url: user?.string('photoUrl'), icon: Icons.person, round: true)],
              title: user == null ? 'No coincide con nadie' : PersonName.from(user).full,
              lines: [_what(r), 'Tel. ${r.string('phone') ?? ''}', requestedOn(r.date('createdAt'))],
              chip: CardChip(pending ? 'Pendiente' : 'Aprobada', color: applicationStatusColor(pending ? ApplicationStatus.pending : ApplicationStatus.approved)),
              onTap: onTap,
            );
          },
        ),
      ),
    );
  }
}

/// Una solicitud «Olvidé algo»: con quién coincide, carné y teléfono (con
/// llamar y WhatsApp). Acciones: Aprobar, Rechazar y Bloquear el teléfono.
class AccessRecoveryScreen extends StatefulWidget {
  final Resource recovery;

  const AccessRecoveryScreen({super.key, required this.recovery});

  @override
  State<AccessRecoveryScreen> createState() => _AccessRecoveryScreenState();
}

class _AccessRecoveryScreenState extends State<AccessRecoveryScreen> {
  late Resource _recovery = widget.recovery;

  /// Lo que se comunica tras aprobar (usuario y/o contraseña propuesta).
  Map<String, String>? _granted;

  Future<void> _resolve(bool approve) async {
    final document = await context.api.patch('/access-recoveries/${_recovery.id}', resourceData('access-recoveries', id: _recovery.id, attributes: {
      'status': approve ? 'approved' : 'rejected',
    }));
    if (!mounted) return;
    final resource = document.resources.isEmpty ? null : document.resource;
    if (!approve) {
      showMessage(context, 'Solicitud rechazada.');
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (resource != null) _recovery = resource;
      _granted = {
        if (resource?.string('username') != null) 'Usuario': resource!.string('username')!,
        if (resource?.string('password') != null) 'Contraseña nueva': resource!.string('password')!,
      };
    });
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    if (!await launchUrl(uri) && mounted) showMessage(context, 'No se pudo abrir el teléfono.');
  }

  Future<void> _whatsApp(String phone) async {
    final uri = Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showMessage(context, 'No se pudo abrir WhatsApp.');
  }

  Future<void> _block(String installationId) async {
    await context.api.patch('/installations/$installationId', resourceData('installations', id: installationId, attributes: {'blocked': true}));
    if (mounted) showMessage(context, 'Teléfono bloqueado.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _recovery;
    final user = widget.recovery.related('user');
    final phone = r.string('phone') ?? '';
    final pending = r.string('status') == 'pending';
    final installationId = widget.recovery.relId('installation')?.id;
    final granted = _granted;
    return AppScaffold(
      title: 'Olvidé algo',
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.check_circle_outline, label: 'Aprobar', enabled: pending && user != null, confirmation: '¿Lo confirmó por una tercera vía (llamada o WhatsApp)? Se le comunicará solo lo que pidió.', onPressed: () => _resolve(true)),
        ActionItem(icon: Icons.cancel_outlined, label: 'Rechazar', enabled: pending, destructive: true, confirmation: '¿Rechazar la solicitud?', onPressed: () => _resolve(false)),
        const ActionItem.divider(),
        ActionItem(icon: Icons.call, label: 'Llamar', enabled: phone.isNotEmpty, onPressed: () => _call(phone)),
        ActionItem(icon: Icons.chat, label: 'Escribir por WhatsApp', enabled: phone.isNotEmpty, onPressed: () => _whatsApp(phone)),
        ActionItem(
          icon: Icons.phonelink_lock,
          label: 'Bloquear el teléfono',
          destructive: true,
          enabled: installationId != null,
          confirmation: 'Ese teléfono no podrá enviar más solicitudes ni escribir sin cuenta. ¿Bloquearlo?',
          onPressed: () => _block(installationId!),
        ),
      ],
      body: ListView(padding: const EdgeInsets.only(top: 4, bottom: 96), children: [
        if (user != null) UserCard.person(Person.from(user)) else const InfoCard(images: [CardImage(icon: Icons.person_off, round: true)], title: 'No coincide con nadie', lines: ['El carné no es de ninguna cuenta.']),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(children: [
            ReadOnlyField(label: 'Qué pidió', value: _what(r), icon: Icons.help_outline),
            ReadOnlyField(label: 'Carné de identidad', value: r.string('identityCard') ?? '', icon: Icons.badge_outlined),
            ReadOnlyField(label: 'Teléfono', value: phone, icon: Icons.phone),
            ReadOnlyField(label: 'Solicitada', value: r.date('createdAt') == null ? '' : formatDay(r.date('createdAt')!), icon: Icons.event),
          ]),
        ),
        if (granted != null) ...[
          const SectionHeader('Comuníquele solo esto'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Por la tercera vía o enviándolo al teléfono que hizo la solicitud. Al entrar con la contraseña nueva deberá cambiarla. No se volverá a mostrar aquí.'),
          ),
          for (final e in granted.entries) CopyShareField(label: e.key, value: e.value),
          if (granted.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aprobada. La persona lo verá en el teléfono desde el que lo pidió.')),
        ],
      ]),
    );
  }
}
