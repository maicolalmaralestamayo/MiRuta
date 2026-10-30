import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../widgets/common.dart';

/// Trabajadores. Los Jefes de itinerario ven los miembros de sus itinerarios;
/// el Administrador puede activar y desactivar.
class WorkersScreen extends StatefulWidget {
  final List<String>? itineraryIds;

  const WorkersScreen({super.key, this.itineraryIds});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  final _view = GlobalKey<AsyncViewState<List<Worker>>>();
  String _search = '';
  String _active = 'true';

  Future<List<Worker>> _load() async {
    final api = context.api;
    final List<String?> itineraries = widget.itineraryIds ?? [null];
    final workers = <Worker>[];
    for (final itinerary in itineraries) {
      final resources = await api.getAll('/workers', query: {
        'include': 'rank',
        'filter[itinerary]': ?itinerary,
        if (_search.isNotEmpty) 'filter[search]': _search,
        if (_active != 'true') 'filter[active]': _active,
      });
      workers.addAll(resources.map(Worker.from));
    }
    return workers;
  }

  Future<void> _toggle(Worker worker) async {
    final activate = !worker.active;
    if (!await confirm(context, activate ? 'Activar' : 'Desactivar', '¿${activate ? 'Activar' : 'Desactivar'} a ${worker.fullName}?', destructive: !activate)) return;
    if (!mounted) return;
    await runAction(context, () => context.api.patch('/workers/${worker.id}', {
          'data': {'type': 'workers', 'id': worker.id, 'attributes': {'active': activate}},
        }));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.me.isAdmin;
    return Scaffold(
      appBar: AppBar(title: Text(widget.itineraryIds == null ? 'Trabajadores' : 'Miembros de mis itinerarios')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre', isDense: true),
                onSubmitted: (value) {
                  _search = value.trim();
                  _view.currentState?.reload();
                },
              ),
            ),
            if (admin) ...[
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _active,
                items: const [
                  DropdownMenuItem(value: 'true', child: Text('Activos')),
                  DropdownMenuItem(value: 'false', child: Text('Inactivos')),
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                ],
                onChanged: (value) {
                  setState(() => _active = value!);
                  _view.currentState?.reload();
                },
              ),
            ],
          ]),
        ),
        Expanded(
          child: AsyncView<List<Worker>>(
            key: _view,
            load: _load,
            builder: (context, workers, reload) => ListView(children: [
              ListTile(title: Text('${workers.length} trabajador(es)')),
              for (final w in workers)
                ListTile(
                  leading: WorkerAvatar(w),
                  title: Text(w.fullName, style: TextStyle(decoration: w.active ? null : TextDecoration.lineThrough)),
                  subtitle: Wrap(spacing: 8, children: [
                    RankBadge(w.rank),
                    if (w.childrenCount > 0) Text('${w.childrenCount} niño(s)'),
                    if (admin && w.cardNumber != null) Text(w.cardNumber!),
                  ]),
                  trailing: admin ? IconButton(icon: Icon(w.active ? Icons.person_off_outlined : Icons.person_add_alt), onPressed: () => _toggle(w)) : null,
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
