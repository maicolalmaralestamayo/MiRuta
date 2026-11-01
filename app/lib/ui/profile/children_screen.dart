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

  /// Quitar un hijo es una solicitud que aprueba un superior.
  Future<void> _remove(Child child) async {
    await context.api.post('/applications', resourceData('applications', attributes: {'type': ApplicationType.childRemoval}, relationships: {
      'child': ResourceId('children', child.id),
    }));
    if (mounted) showMessage(context, 'Solicitud enviada');
  }

  String _date(String value) => formatDate(DateTime.parse(value));

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
        label: const Text('Declarar hijos'),
      ),
      body: AsyncView<List<Child>>(
        key: _view,
        load: _load,
        builder: (context, children, reload) => children.isEmpty
            ? const EmptyView(icon: Icons.child_care, message: 'No ha declarado hijos.')
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final child in children)
                  ListTile(
                    leading: const Icon(Icons.child_care),
                    title: Text(child.fullName),
                    isThreeLine: true,
                    subtitle: Text([
                      if (child.birthDate != null) 'Fecha Nac.: ${_date(child.birthDate!)}',
                      if (child.eligibleUntil != null) 'Derecho a viajar: ${_date(child.eligibleUntil!)}',
                      if (!child.declared) 'Pendiente de aprobar',
                      if (!child.eligible) 'Ya no tiene derecho a viajar',
                    ].join('\n')),
                    trailing: child.declared ? DeleteButton(what: 'a ${child.fullName} de sus hijos (se enviará una solicitud)', tooltip: 'Quitar hijo', onDelete: () => _remove(child)) : null,
                  ),
              ]),
      ),
    );
  }
}
