import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'application_forms.dart';

/// Solicitudes: enviar nuevas, ver las propias (historial) y resolver las de otros.
class ApplicationsScreen extends StatelessWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final resolves = me.isAdmin || me.roles.isTransportChief || me.roles.isItineraryChief;
    return DefaultTabController(
      length: resolves ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Solicitudes'),
          bottom: resolves ? const TabBar(tabs: [Tab(text: 'Mis solicitudes'), Tab(text: 'Por resolver')]) : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _newApplication(context),
          icon: const Icon(Icons.add),
          label: const Text('Nueva'),
        ),
        body: TabBarView(children: [
          const _ApplicationList(mine: true),
          if (resolves) const _ApplicationList(mine: false),
        ]),
      ),
    );
  }

  Future<void> _newApplication(BuildContext context) async {
    final me = context.me;
    final types = [
      ApplicationType.itineraryMembership,
      ApplicationType.itineraryChief,
      if (!me.roles.isDriver) ApplicationType.driver,
      if (!me.roles.isTransportChief) ApplicationType.transportChief,
      ApplicationType.childAddition,
      ApplicationType.absence,
    ];
    final type = await pickFrom<String>(context, '¿Qué quieres solicitar?', types, ApplicationType.label);
    if (type != null && context.mounted) await showApplicationForm(context, type);
  }
}

class _ApplicationList extends StatefulWidget {
  final bool mine;

  const _ApplicationList({required this.mine});

  @override
  State<_ApplicationList> createState() => _ApplicationListState();
}

class _ApplicationListState extends State<_ApplicationList> {
  final _view = GlobalKey<AsyncViewState<List<Application>>>();

  Future<List<Application>> _load() async {
    final document = await context.api.get('/applications', query: {
      if (widget.mine) 'filter[mine]': 'true',
      if (!widget.mine) 'filter[toResolve]': 'true',
      'include': 'worker,resolvedBy,itinerary,stop,absenceType',
      'page[size]': 100,
    });
    return document.resources.map(Application.from).toList();
  }

  Future<void> _resolve(Application application, String status) async {
    final note = await promptText(context, status == 'approved' ? 'Aprobar' : 'Rechazar', label: 'Nota (opcional)', maxLines: 2);
    if (note == null || !mounted) return;
    await context.api.patch('/applications/${application.id}', {
      'data': {'type': 'applications', 'id': application.id, 'attributes': {'status': status, if (note.isNotEmpty) 'resolutionNote': note}},
    });
    if (mounted) showMessage(context, status == 'approved' ? 'Solicitud aprobada' : 'Solicitud rechazada');
    _view.currentState?.reload();
  }

  Future<void> _cancel(Application application) async {
    if (!await confirm(context, 'Cancelar solicitud', '¿Cancelar la solicitud de ${ApplicationType.label(application.type).toLowerCase()}?')) return;
    if (!mounted) return;
    await context.api.patch('/applications/${application.id}', {
      'data': {'type': 'applications', 'id': application.id, 'attributes': {'status': 'cancelled'}},
    });
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Application>>(
      key: _view,
      load: _load,
      builder: (context, applications, reload) {
        if (applications.isEmpty) {
          return EmptyView(icon: Icons.assignment_turned_in_outlined, message: widget.mine ? 'No has enviado solicitudes.' : 'No hay solicitudes por resolver.');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: applications.length,
          itemBuilder: (context, index) {
            final a = applications[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(ApplicationType.label(a.type), style: Theme.of(context).textTheme.titleMedium)),
                    StatusChip(ApplicationType.statusLabel(a.status), color: _statusColor(a.status)),
                  ]),
                  if (!widget.mine && a.worker != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        WorkerAvatar(a.worker!, radius: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${a.worker!.fullName}${a.worker!.pass == null ? '' : ' · Pase ${a.worker!.pass}'}')),
                      ]),
                    ),
                  if (a.assigned) Text('Asignado por un superior', style: Theme.of(context).textTheme.bodySmall),
                  if (a.possibleDuplicate)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: StatusChip('Posible duplicado: ya hay un niño con el mismo nombre, apellido y fecha', color: saturatedColor, icon: Icons.warning_amber),
                    ),
                  if (a.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(a.summary)),
                  if (a.observation != null && a.observation!.isNotEmpty) Text(a.observation!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('Enviada ${formatDateTime(a.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                  if (a.resolvedAt != null)
                    Text('Resuelta ${formatDateTime(a.resolvedAt!)}${a.resolverName == null ? '' : ' por ${a.resolverName}'}', style: Theme.of(context).textTheme.bodySmall),
                  if (a.resolutionNote != null) Text('Nota: ${a.resolutionNote}', style: Theme.of(context).textTheme.bodySmall),
                  if (a.isPending)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: 8, children: [
                        if (widget.mine) BusyButton.text(onPressed: () => _cancel(a), child: const Text('Cancelar')),
                        if (!widget.mine) BusyButton.text(onPressed: () => _resolve(a, 'rejected'), child: const Text('Rechazar')),
                        if (!widget.mine) BusyButton(onPressed: () => _resolve(a, 'approved'), child: const Text('Aprobar')),
                      ]),
                    ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Color _statusColor(String status) => const {
        'pending': Colors.orange,
        'approved': Colors.green,
        'rejected': Colors.red,
        'cancelled': Colors.grey,
      }[status] ?? Colors.grey;
}
