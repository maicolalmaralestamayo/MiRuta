import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

String _what(Resource r) {
  final user = r.boolean('forgotUsername');
  final password = r.boolean('forgotPassword');
  return user && password ? 'Olvidó el usuario y la contraseña' : (user ? 'Olvidó el usuario' : 'Olvidó la contraseña');
}

/// «Olvidé algo» (Administrador; docs/11 §11.7, maqueta G18 n.º 19): tras
/// confirmar los datos por otra vía (llamada o WhatsApp) se aprueba o se
/// rechaza. Al aprobar se comunica solo lo pedido.
class AccessRecoveriesScreen extends StatefulWidget {
  const AccessRecoveriesScreen({super.key});

  @override
  State<AccessRecoveriesScreen> createState() => _AccessRecoveriesScreenState();
}

class _AccessRecoveriesScreenState extends State<AccessRecoveriesScreen> {
  final _view = GlobalKey<DataViewState<List<Resource>>>();

  Future<List<Resource>> _load() async => context.read<Session>().api.getAll('/access-recoveries', query: {'include': 'user'});

  String _phoneDigits(Resource r) => (r.string('phone') ?? '').replaceAll(RegExp(r'\D'), '');

  Future<void> _resolve(Resource r, String status) async {
    final api = context.read<Session>().api;
    final result = (await api.patch('/access-recoveries/${r.id}', resourceData('access-recoveries', id: r.id, attributes: {'status': status}))).resource;
    if (!mounted) return;
    if (status == 'approved') {
      final lines = [
        if (result.string('username') != null) 'Usuario: ${result.string('username')}',
        if (result.string('password') != null) 'Contraseña: ${result.string('password')} (deberá cambiarla al entrar)',
      ];
      final text = 'MiRuta: se aprobó su solicitud. ${lines.join('. ')}. También puede verlo en la app, en «Olvidé usuario/contraseña».';
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          icon: const Icon(Icons.check_circle_outline, size: 32, color: green),
          title: 'Solicitud aprobada',
          content: SelectableText(lines.isEmpty ? 'La persona lo verá en su teléfono.' : lines.join('\n')),
          buttons: [
            primaryButton(context, 'Enviar por WhatsApp', Icons.send,
                () => launchUrl(Uri.parse('https://wa.me/${_phoneDigits(r)}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication)),
            cancelButton(context, label: 'Cerrar'),
          ],
        ),
      );
    }
    _view.currentState?.reload();
  }

  Future<void> _open(Resource r) async {
    final user = r.related('user');
    final pending = r.string('status') == 'pending';
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        icon: const Icon(Icons.lock_reset, size: 32),
        title: user?.string('fullName') ?? 'No coincide con nadie',
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_what(r)),
          const SizedBox(height: 6),
          Text('Correo: ${r.string('email') ?? ''}'),
          Text('Teléfono: ${r.string('phone') ?? ''}'),
          Text('Pedida: ${formatDateTime(r.date('createdAt'))}'),
          if (r.attributes['matched'] == false) const Padding(padding: EdgeInsets.only(top: 6), child: Text('El correo no coincide con ninguna persona registrada.', style: TextStyle(color: red))),
          const SizedBox(height: 8),
          const Text('Antes de aprobar, confirme los datos llamando o escribiendo a ese teléfono.'),
        ]),
        buttons: [
          if (pending && r.attributes['matched'] != false) primaryButton(context, 'Aprobar', Icons.check, () => Navigator.pop(context, 'approved')),
          if (pending) dangerButton(context, 'Rechazar', Icons.block, () => Navigator.pop(context, 'rejected')),
          otherButton(context, 'Llamar', Icons.call, () => launchUrl(Uri.parse('tel:${_phoneDigits(r)}'))),
          otherButton(context, 'WhatsApp', Icons.chat, () => launchUrl(Uri.parse('https://wa.me/${_phoneDigits(r)}'), mode: LaunchMode.externalApplication)),
          cancelButton(context, label: pending ? 'Cancelar' : 'Cerrar'),
        ],
      ),
    );
    if (action != null && mounted) await runAction(context, () => _resolve(r, action), label: action == 'approved' ? 'Aprobando Solicitud' : 'Rechazando Solicitud');
  }

  Widget _card(Resource r) {
    final user = r.related('user');
    final status = r.string('status');
    final (label, color) = switch (status) {
      'pending' => ('Pendiente', amber),
      'approved' => ('Aprobada', green),
      'completed' => ('Entregada', green),
      'rejected' => ('Rechazada', red),
      _ => ('Caducada', grey),
    };
    return InfoCard(
      images: const [CardImage(icon: Icons.lock_reset)],
      title: user?.string('fullName') ?? 'No coincide con nadie',
      lines: [_what(r), formatDateTime(r.date('createdAt'))],
      chip: Chip2(label, color),
      onTap: () => _open(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Olvidé algo',
      tab: MainTab.more,
      body: DataView<List<Resource>>(
        what: 'Solicitudes',
        key: _view,
        kinds: const {'access-recoveries'},
        load: _load,
        builder: (context, list, reload) => ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          FoldSection<Resource>(storageKey: 'olvide.pendientes', title: 'Pendientes', items: list.where((r) => r.string('status') == 'pending').toList(), builder: _card, emptyText: 'No hay solicitudes pendientes.'),
          FoldSection<Resource>(storageKey: 'olvide.atendidas', title: 'Atendidas', items: list.where((r) => r.string('status') != 'pending').toList(), builder: _card, initiallyOpen: false),
        ]),
      ),
    );
  }
}
