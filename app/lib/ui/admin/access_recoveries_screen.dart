import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// "No puedo entrar" (solo el Administrador, docs/08-version-2.md §8.6): se
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
          ? '¿Ya comprobaste por tu cuenta que es esa persona? En su teléfono podrá ver su usuario o elegir una contraseña nueva.'
          : '¿Rechazar la solicitud?',
      accept: approve ? 'Aprobar' : 'Rechazar',
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

  Future<void> _block(String installationId) async {
    if (!await confirm(context, 'Bloquear el teléfono', 'Ese teléfono no podrá enviar más solicitudes ni escribir sin cuenta.', accept: 'Bloquear', destructive: true)) return;
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
      appBar: AppBar(title: const Text('No puedo entrar')),
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
                          const SizedBox(height: 6),
                          Text('Escribió: Entidad ${recovery.string('entityAbbreviation')} · Pase ${recovery.integer('pass')}'),
                          if (worker == null)
                            Text('No coincide con ningún trabajador con cuenta activada.', style: TextStyle(color: Theme.of(context).colorScheme.error))
                          else
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: WorkerAvatar(worker),
                              title: Text(worker.fullName),
                              subtitle: Text([worker.entity?.abbreviation, ?itinerary].whereType<String>().join(' · ')),
                            ),
                          Row(children: [
                            Expanded(child: SelectableText('Teléfono: $phone')),
                            IconButton(tooltip: 'Llamar', icon: const Icon(Icons.call), onPressed: phone.isEmpty ? null : () => _call(phone)),
                          ]),
                          Text('Pedida ${formatDateTime(recovery.date('createdAt')!)} · caduca ${formatDateTime(recovery.date('expiresAt')!)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          const Text('Comprueba por tu cuenta que es esa persona antes de aprobar.', style: TextStyle(fontStyle: FontStyle.italic)),
                          if (status == 'pending')
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 8, children: [
                                if (installationId != null) BusyButton.text(onPressed: () => _block(installationId), child: const Text('Bloquear teléfono')),
                                BusyButton.text(onPressed: () => _resolve(recovery, 'rejected'), child: const Text('Rechazar')),
                                if (worker != null) BusyButton(onPressed: () => _resolve(recovery, 'approved'), child: const Text('Aprobar')),
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
