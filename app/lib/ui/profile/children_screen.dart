import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../applications/application_forms.dart';
import '../widgets/common.dart';

/// Hijos declarados (y pendientes de aprobar).
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final _view = GlobalKey<AsyncViewState<List<Child>>>();

  Future<List<Child>> _load() async =>
      (await context.api.getAll('/children', query: {'filter[worker]': context.me.id})).map(Child.from).toList();

  Future<void> _remove(Child child) async {
    if (!await confirm(context, 'Quitar hijo', '¿Solicitar quitar a ${child.fullName}?')) return;
    if (!mounted) return;
    await runAction(context, () => context.api.post('/applications', resourceData('applications', attributes: {'type': ApplicationType.childRemoval}, relationships: {
          'child': ResourceId('children', child.id),
        })), success: 'Solicitud enviada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis hijos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showApplicationForm(context, ApplicationType.childAddition);
          _view.currentState?.reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Declarar hijo'),
      ),
      body: AsyncView<List<Child>>(
        key: _view,
        load: _load,
        builder: (context, children, reload) => children.isEmpty
            ? const EmptyView(icon: Icons.child_care, message: 'No has declarado hijos.\nLos niños viajan en las piernas y no ocupan plaza.')
            : ListView(children: [
                for (final child in children)
                  ListTile(
                    leading: const Icon(Icons.child_care),
                    title: Text(child.fullName),
                    subtitle: Text([
                      if (!child.declared) 'Pendiente de aprobar',
                      if (child.eligibleUntil != null) 'Puede viajar hasta el ${formatDate(DateTime.parse(child.eligibleUntil!))}',
                      if (!child.eligible) 'Ya no tiene derecho a viajar',
                    ].join(' · ')),
                    trailing: child.declared ? IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _remove(child)) : null,
                  ),
              ]),
      ),
    );
  }
}
