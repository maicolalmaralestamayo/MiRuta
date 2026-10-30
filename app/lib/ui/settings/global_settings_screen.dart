import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/user_settings.dart';
import '../widgets/common.dart';
import 'setting_editor.dart';

/// Ajustes generales. Cada uno lo cambia quien indica su definición (el
/// Administrador siempre).
class GlobalSettingsScreen extends StatefulWidget {
  const GlobalSettingsScreen({super.key});

  @override
  State<GlobalSettingsScreen> createState() => _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends State<GlobalSettingsScreen> {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, List<Resource>)>>();

  Future<(Map<String, SettingDefinition>, List<Resource>)> _load() async {
    final api = context.api;
    return (await loadSettingDefinitions(api), (await api.get('/settings')).resources);
  }

  Future<void> _edit(SettingDefinition definition, String current) async {
    final value = await editSettingValue(context, definition, current);
    if (value == null || !mounted) return;
    await runAction(context, () => context.api.patch('/settings/${definition.key}', {
          'data': {'type': 'settings', 'id': definition.key, 'attributes': {'value': value}},
        }));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes generales')),
      body: AsyncView<(Map<String, SettingDefinition>, List<Resource>)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final (definitions, settings) = data;
          final editable = settings.where((s) => s.boolean('editable')).toList();
          final globalOnly = editable.where((s) => definitions[s.id]?.userOverridable == false).toList();
          final defaults = editable.where((s) => definitions[s.id]?.userOverridable == true).toList();
          Widget tile(Resource s) {
            final definition = definitions[s.id]!;
            final value = s.string('value') ?? '';
            return ListTile(
              title: Text(definition.name),
              subtitle: Text([describeSetting(definition, value), if (definition.description != null) definition.description!].join('\n')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(definition, value),
            );
          }

          return ListView(children: [
            const SectionTitle('Generales'),
            for (final s in globalOnly) tile(s),
            if (defaults.isNotEmpty) ...[
              const SectionTitle('Valores por defecto de los ajustes de usuario'),
              for (final s in defaults) tile(s),
            ],
          ]);
        },
      ),
    );
  }
}
