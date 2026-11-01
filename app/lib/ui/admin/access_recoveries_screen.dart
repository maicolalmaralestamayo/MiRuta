import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// "Olvidé algo" (solo el Administrador, docs/08-version-2.md §8.6): se
/// ve con quién coinciden los datos; tras hablar con la persona por su
/// cuenta, se aprueba o se rechaza. Lo aprobado solo vale en el teléfono
/// desde el que se pidió.
class AccessRecoveriesScreen extends StatefulWidget {
  const AccessRecoveriesScreen({super.key});

  @override
  State<AccessRecoveriesScreen> createState() => _AccessRecoveriesScreenState();
}

class _AccessRecoveriesScreenState extends State<AccessRecoveriesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Resource>>>();

  Future<List<Resource>> _load() async => (await context.api.get('/access-recoveries', query: {
        'include': 'worker,worker.user,worker.entity,worker.itinerary,installation',
        'page[size]': 100,
      }))
          .resources;

  Future<void> _resolve(Resource recovery, String status) async {
    final approve = status == 'approved';
    if (!await confirm(
      context,
      approve ? 'Aprobar' : 'Rechazar',
      approve
          ? '¿Aprobar la solicitud? En su teléfono podrá ver su usuario o elegir una contraseña nueva.'
          : '¿Rechazar la solicitud?',
      accept: approve ? 'Aprobar solicitud' : 'Rechazar solicitud',
      destructive: !approve,
    )) {
      return;
    }
    if (!mounted) return;
    await context.api.patch('/access-recoveries/${recovery.id}', {
      'data': {'type': 'access-recoveries', 'id': recovery.id, 'attributes': {'status': status}},
    });
    _view.currentState?.reload();
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
    if (!await launchUrl(uri) && mounted) showMessage(context, 'No se pudo abrir el teléfono.');
  }

  /// Abre el chat de WhatsApp con ese número (sin "+" ni espacios).
  Future<void> _whatsApp(String phone) async {
    final uri = Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showMessage(context, 'No se pudo abrir WhatsApp.');
  }

  Widget _readOnly(String label, String value, {Widget? suffix}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, isDense: true, suffixIcon: suffix),
          child: SelectableText(value),
        ),
      );

  Future<void> _block(String installationId) async {
    if (!await confirm(context, 'Bloquear el teléfono', 'Ese teléfono no podrá enviar más solicitudes ni escribir sin cuenta.', accept: 'Bloquear teléfono', destructive: true)) return;
    if (!mounted) return;
    await context.api.patch('/installations/$installationId', resourceData('installations', id: installationId, attributes: {'blocked': true}));
    if (mounted) showMessage(context, 'Teléfono bloqueado');
  }

  String _what(Resource r) {
    final user = r.boolean('forgotUsername');
    final password = r.boolean('forgotPassword');
    return user && password ? 'Olvidó el usuario y la contraseña' : (user ? 'Olvidó el usuario' : 'Olvidó la contraseña');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Olvidé algo')),
      body: AsyncView<List<Resource>>(
        key: _view,
        load: _load,
        builder: (context, recoveries, reload) => recoveries.isEmpty
            ? const EmptyView(icon: Icons.lock_reset, message: 'No hay solicitudes abiertas.')
            : ListView(children: [
                for (final recovery in recoveries)
                  Builder(builder: (context) {
                    final related = recovery.related('worker');
                    final worker = related == null ? null : Worker.from(related);
                    final itinerary = related?.related('itinerary')?.string('name');
                    final phone = recovery.string('phone') ?? '';
                    final status = recovery.string('status');
                    final installationId = recovery.relId('installation')?.id;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(_what(recovery), style: Theme.of(context).textTheme.titleMedium)),
                            StatusChip(status == 'approved' ? 'Aprobada' : 'Pendiente', color: status == 'approved' ? Colors.green : Colors.orange),
                          ]),
                          if (worker == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('No coincide con ningún trabajador con cuenta activada.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            )
                          else
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: WorkerAvatar(worker),
                              title: Text(worker.fullName),
                              subtitle: itinerary == null ? null : Text(itinerary),
                            ),
                          _readOnly('Entidad', recovery.string('entityAbbreviation') ?? ''),
                          _readOnly('Pase', '${recovery.integer('pass') ?? ''}'),
                          _readOnly(
                            'Teléfono',
                            phone,
                            suffix: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(tooltip: 'Llamar', icon: const Icon(Icons.call), onPressed: phone.isEmpty ? null : () => _call(phone)),
                              IconButton(tooltip: 'Escribir por WhatsApp', icon: const Icon(Icons.chat), onPressed: phone.isEmpty ? null : () => _whatsApp(phone)),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          Text('Solicitada ${formatDateTime(recovery.date('createdAt')!)} · caduca ${formatDateTime(recovery.date('expiresAt')!)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (status == 'pending')
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 8, children: [
                                if (installationId != null)
                                  BusyButton.text(onPressed: () => _block(installationId), icon: const Icon(Icons.phonelink_lock), child: const Text('Bloquear teléfono')),
                                BusyButton.text(onPressed: () => _resolve(recovery, 'rejected'), icon: const Icon(Icons.close), child: const Text('Rechazar solicitud')),
                                if (worker != null) BusyButton(onPressed: () => _resolve(recovery, 'approved'), icon: const Icon(Icons.check), child: const Text('Aprobar solicitud')),
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
