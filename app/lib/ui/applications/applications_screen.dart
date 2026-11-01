import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../../services/templates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'application_forms.dart';

/// Solicitudes: enviar nuevas, ver las propias (historial) y resolver las de otros.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  /// Cambia para volver a cargar "Mis solicitudes" tras enviar una.
  int _version = 0;

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
          onPressed: _newApplication,
          icon: const Icon(Icons.add),
          label: const Text('Nueva'),
        ),
        body: TabBarView(children: [
          _ApplicationList(key: ValueKey('mine-$_version'), mine: true),
          if (resolves) const _ApplicationList(mine: false),
        ]),
      ),
    );
  }

  Future<void> _newApplication() async {
    final me = context.me;
    final types = [
      ApplicationType.itineraryMembership,
      if (me.itineraryId != null) ApplicationType.itineraryLeave,
      ApplicationType.itineraryChief,
      if (!me.roles.isTransportChief) ApplicationType.transportChief,
      if (!me.roles.isDriver) ApplicationType.driver,
      ApplicationType.childAddition,
      ApplicationType.absence,
    ];
    final type = await pickFrom<String>(context, '¿Qué desea solicitar?', types, ApplicationType.label);
    if (type == null || !mounted) return;
    if (type == ApplicationType.itineraryLeave) {
      await _leaveItinerary();
    } else if (await showApplicationForm(context, type)) {
      setState(() => _version++);
    }
  }

  /// Baja inmediata del itinerario aprobado (docs/09 §14), con confirmación.
  Future<void> _leaveItinerary() async {
    if (!await confirm(context, 'Darme de baja del itinerario', '¿Darse de baja del itinerario? Se avisará a sus superiores.',
        accept: 'Darme de baja', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final session = context.session;
    final ok = await runAction(
      context,
      () => session.api.post('/applications', resourceData('applications', attributes: {'type': ApplicationType.itineraryLeave})),
      success: 'Se dio de baja del itinerario',
    );
    if (!ok) return;
    await session.reloadMe().catchError((_) {});
    if (mounted) setState(() => _version++);
  }
}

class _ApplicationList extends StatefulWidget {
  final bool mine;

  const _ApplicationList({super.key, required this.mine});

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

  /// Agrupa las solicitudes enviadas juntas (varios hijos) conservando el orden.
  List<List<Application>> _groups(List<Application> applications) {
    final groups = <String, List<Application>>{};
    for (final a in applications) {
      groups.putIfAbsent(a.groupId ?? a.id, () => []).add(a);
    }
    return groups.values.toList();
  }

  Future<void> _patch(Application application, Map<String, dynamic> attributes) => context.api.patch('/applications/${application.id}', {
        'data': {'type': 'applications', 'id': application.id, 'attributes': attributes},
      });

  Future<void> _approve(Application application) async {
    await _patch(application, {'status': 'approved'});
    if (mounted) showMessage(context, 'Solicitud aprobada');
    _view.currentState?.reload();
  }

  Future<void> _reject(Application application) async {
    final reason = await _askReason();
    if (reason == null || !mounted) return;
    await _patch(application, {'status': 'rejected', 'resolutionNote': reason});
    if (mounted) showMessage(context, 'Solicitud rechazada');
    _view.currentState?.reload();
  }

  /// Motivo del rechazo: obligatorio (lo exige el servidor).
  Future<String?> _askReason() {
    final form = GlobalKey<FormState>();
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motivo', hintText: 'La parada no pertenece a ese itinerario'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escriba el motivo del rechazo' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: overloadColor),
            icon: const Icon(Icons.close),
            label: const Text('Rechazar solicitud'),
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, controller.text.trim());
            },
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(Application application) async {
    if (!await confirm(context, 'Cancelar solicitud', '¿Cancelar la solicitud de ${ApplicationType.label(application.type).toLowerCase()}?',
        accept: 'Cancelar solicitud', destructive: true)) {
      return;
    }
    if (!mounted) return;
    await _patch(application, {'status': 'cancelled'});
    _view.currentState?.reload();
  }

  /// Ausencia indefinida aprobada: el trabajador le pone fechas (PATCH sin status).
  Future<void> _setAbsenceDates(Application application) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Fechas de la ausencia',
    );
    if (range == null || !mounted) return;
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    await _patch(application, {'startsOn': day(range.start), 'endsOn': day(range.end)});
    if (mounted) showMessage(context, 'Fechas de la ausencia guardadas');
    _view.currentState?.reload();
  }

  String? _resolution(Application a) {
    final by = a.resolverName == null ? '' : ' por ${a.resolverName}';
    final at = a.resolvedAt == null ? '' : ' el ${formatDateTime(a.resolvedAt!.toLocal())}';
    return switch (a.status) {
      'approved' => 'Aprobada$at$by',
      'rejected' => 'Rechazada$at$by',
      'cancelled' => 'Cancelada$at',
      _ => null,
    };
  }

  /// Estado, resolución y acciones de una solicitud (o de un hijo de un grupo).
  List<Widget> _details(Application a) {
    final small = Theme.of(context).textTheme.bodySmall;
    final resolution = _resolution(a);
    final note = a.resolutionNote;
    return [
      if (a.possibleDuplicate)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: StatusChip('Posible duplicado: ya hay un niño con el mismo nombre, apellido y fecha', color: saturatedColor, icon: Icons.warning_amber),
        ),
      if (resolution != null) Text(resolution, style: small),
      if (note != null && note.isNotEmpty) Text(a.status == 'rejected' ? 'Motivo: $note' : 'Nota: $note', style: small),
      if (a.isPending || (widget.mine && a.type == ApplicationType.absence && a.status == 'approved' && a.indefinite))
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: [
            if (widget.mine && a.isPending)
              BusyButton.text(onPressed: () => _cancel(a), icon: const Icon(Icons.cancel_outlined), child: const Text('Cancelar solicitud')),
            if (widget.mine && !a.isPending)
              BusyButton.tonal(onPressed: () => _setAbsenceDates(a), icon: const Icon(Icons.event), child: const Text('Poner fechas a la ausencia')),
            if (!widget.mine)
              BusyButton.outlined(
                onPressed: () => _reject(a),
                icon: const Icon(Icons.close, color: overloadColor),
                child: const Text('Rechazar solicitud'),
              ),
            if (!widget.mine) BusyButton(onPressed: () => _approve(a), icon: const Icon(Icons.check), child: const Text('Aprobar solicitud')),
          ]),
        ),
    ];
  }

  Widget _card(List<Application> group) {
    final first = group.first;
    final theme = Theme.of(context);
    final single = group.length == 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(ApplicationType.label(first.type), style: theme.textTheme.titleMedium)),
            if (single) StatusChip(ApplicationType.statusLabel(first.status), color: _statusColor(first.status)),
          ]),
          if (!widget.mine && first.worker != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                WorkerAvatar(first.worker!, radius: 14),
                const SizedBox(width: 8),
                Expanded(child: Text('${first.worker!.fullName}${first.worker!.pass == null ? '' : ' · Pase ${first.worker!.pass}'}')),
              ]),
            ),
          if (first.assigned) Text('Asignada por un superior', style: theme.textTheme.bodySmall),
          if (single && first.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(first.summary)),
          if (first.observation != null && first.observation!.isNotEmpty) Text(first.observation!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('Enviada el ${formatDateTime(first.createdAt.toLocal())}', style: theme.textTheme.bodySmall),
          if (single)
            ..._details(first)
          else
            for (final a in group) ...[
              const Divider(height: 16),
              Row(children: [
                const Icon(Icons.child_care, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(a.childName ?? a.summary, style: theme.textTheme.titleSmall)),
                StatusChip(ApplicationType.statusLabel(a.status), color: _statusColor(a.status)),
              ]),
              ..._details(a),
            ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Application>>(
      key: _view,
      load: _load,
      builder: (context, applications, reload) {
        if (applications.isEmpty) {
          return EmptyView(icon: Icons.assignment_turned_in_outlined, message: widget.mine ? 'No ha enviado solicitudes.' : 'No hay solicitudes por resolver.');
        }
        final groups = _groups(applications);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: groups.length,
          itemBuilder: (context, index) => _card(groups[index]),
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
