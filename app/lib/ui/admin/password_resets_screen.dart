import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Contraseñas olvidadas (solo el Administrador): enviar el código por
/// WhatsApp, marcar como enviado o cancelar.
class PasswordResetsScreen extends StatefulWidget {
  const PasswordResetsScreen({super.key});

  @override
  State<PasswordResetsScreen> createState() => _PasswordResetsScreenState();
}

class _PasswordResetsScreenState extends State<PasswordResetsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Resource>>>();

  Future<List<Resource>> _load() async =>
      (await context.api.get('/password-resets', query: {'include': 'worker.rank', 'page[size]': 100})).resources;

  /// Código con un guion en medio para que se lea mejor: ABCD-EFGH.
  String _pretty(String code) => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  Future<void> _whatsApp(Resource reset, Worker? worker) async {
    final phone = (reset.string('phone') ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final expires = reset.date('expiresAt');
    final text = 'Hola${worker == null ? '' : ' ${worker.firstName}'}. Tu código para entrar en MiTransporte es ${_pretty(reset.string('code') ?? '')}'
        '${expires == null ? '' : ' (válido hasta el ${formatDateTime(expires)})'}. Al entrar tendrás que elegir una contraseña nueva.';
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showMessage(context, 'No se pudo abrir WhatsApp.');
      return;
    }
    if (!mounted) return;
    if (await confirm(context, '¿Se envió el código?', 'Márcalo como enviado si ya se lo mandaste por WhatsApp.', accept: 'Enviado') && mounted) {
      await _setStatus(reset, 'sent');
    }
  }

  Future<void> _setStatus(Resource reset, String status) async {
    await runAction(context, () => context.api.patch('/password-resets/${reset.id}', {
          'data': {'type': 'password-resets', 'id': reset.id, 'attributes': {'status': status}},
        }));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contraseñas olvidadas')),
      body: AsyncView<List<Resource>>(
        key: _view,
        load: _load,
        builder: (context, resets, reload) => resets.isEmpty
            ? const EmptyView(icon: Icons.lock_reset, message: 'No hay solicitudes abiertas.')
            : ListView(children: [
                for (final reset in resets)
                  Builder(builder: (context) {
                    final related = reset.related('worker');
                    final worker = related == null ? null : Worker.from(related);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            if (worker != null) WorkerAvatar(worker),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(worker?.fullName ?? '', style: Theme.of(context).textTheme.titleMedium),
                                if (worker != null) RankBadge(worker.rank),
                              ]),
                            ),
                            StatusChip(reset.string('status') == 'sent' ? 'Enviado' : 'Pendiente', color: reset.string('status') == 'sent' ? Colors.green : Colors.orange),
                          ]),
                          const SizedBox(height: 8),
                          Text('Teléfono: ${reset.string('phone') ?? ''}'),
                          SelectableText('Código: ${_pretty(reset.string('code') ?? '')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2)),
                          Text('Pedido ${formatDateTime(reset.date('createdAt')!)} · caduca ${formatDateTime(reset.date('expiresAt')!)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if ((reset.integer('failedAttempts') ?? 0) > 0)
                            Text('${reset.integer('failedAttempts')} intento(s) fallido(s)', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          const SizedBox(height: 4),
                          const Text('Comprueba que la solicitud es de esa persona antes de enviar el código.', style: TextStyle(fontStyle: FontStyle.italic)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(spacing: 8, children: [
                              TextButton(onPressed: () => _setStatus(reset, 'cancelled'), child: const Text('Cancelar')),
                              FilledButton.icon(onPressed: () => _whatsApp(reset, worker), icon: const Icon(Icons.chat), label: const Text('Enviar por WhatsApp')),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  }),
              ]),
      ),
    );
  }
}
