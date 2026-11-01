import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/user_settings.dart';
import '../widgets/common.dart';
import 'setting_editor.dart';

/// Ajustes en tres niveles (docs/08-version-2.md §8.2):
/// - de la app: solo el Administrador (caducidades, contraseñas, mínimos…);
/// - de la Entidad: su Jefe de Transporte (y el Administrador), incluidos los
///   valores por defecto de los ajustes de cada usuario.
class GlobalSettingsScreen extends StatefulWidget {
  final bool entityLevel;

  const GlobalSettingsScreen.app({super.key}) : entityLevel = false;

  const GlobalSettingsScreen.entity({super.key}) : entityLevel = true;

  @override
  State<GlobalSettingsScreen> createState() => _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends State<GlobalSettingsScreen> {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, List<Resource>)>>();

  String get _path => widget.entityLevel ? '/entity-settings' : '/settings';

  Future<(Map<String, SettingDefinition>, List<Resource>)> _load() async {
    final api = context.api;
    final settings = (await api.get(_path, query: widget.entityLevel ? context.entityFilter : null)).resources;
    return (await loadSettingDefinitions(api), settings);
  }

  Future<void> _edit(SettingDefinition definition, String current) async {
    final value = await editSettingValue(context, definition, current);
    if (value == null || !mounted) return;
    final query = widget.entityLevel ? context.entityFilter : const <String, dynamic>{};
    final suffix = query.isEmpty ? '' : '?filter[entity]=${query['filter[entity]']}';
    await runAction(context, () => context.api.patch('$_path/${definition.key}$suffix', {
          'data': {'type': widget.entityLevel ? 'entity-settings' : 'settings', 'id': definition.key, 'attributes': {'value': value}},
        }));
    _view.currentState?.reload();
  }

  Future<void> _reset(SettingDefinition definition) async {
    final query = context.entityFilter;
    final suffix = query.isEmpty ? '' : '?filter[entity]=${query['filter[entity]']}';
    await context.api.delete('$_path/${definition.key}$suffix');
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    if (widget.entityLevel && me.isAdmin && context.session.adminEntity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ajustes de la Entidad')),
        body: const EmptyView(icon: Icons.apartment_outlined, message: 'Elige primero una Entidad en Gestión.'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.entityLevel ? 'Ajustes de ${context.session.adminEntity?.abbreviation ?? me.entity?.abbreviation ?? 'la Entidad'}' : 'Ajustes de la app')),
      body: AsyncView<(Map<String, SettingDefinition>, List<Resource>)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final (definitions, settings) = data;
          final rows = settings.where((s) => widget.entityLevel || s.boolean('editable')).toList();
          final ownOnly = rows.where((s) => definitions[s.id]?.userOverridable == false).toList();
          final defaults = rows.where((s) => definitions[s.id]?.userOverridable == true).toList();

          Widget tile(Resource s) {
            final definition = definitions[s.id]!;
            final value = s.string('value') ?? '';
            final custom = s.boolean('isCustom');
            final small = Theme.of(context).textTheme.bodySmall;
            // Explicación de una línea y el valor; se edita tocándolo (docs/09 §28/§31).
            return BusyListTile(
              title: Text(definition.name),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((definition.description ?? '').isNotEmpty) Text(definition.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                Text(describeSetting(definition, value), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (widget.entityLevel && custom)
                  Text('Propio de la Entidad (en la app: ${describeSetting(definition, s.string('appValue') ?? '')})', maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              ]),
              trailing: widget.entityLevel && custom
                  ? BusyIconButton(tooltip: 'Volver al valor de la app', icon: const Icon(Icons.undo), onPressed: () => _reset(definition))
                  : definition.valueType == 'boolean'
                      ? IgnorePointer(child: Switch(value: value == '1', onChanged: (_) {}))
                      : null,
              onTap: () => _edit(definition, value),
            );
          }

          return ListView(children: [
            SectionTitle(widget.entityLevel ? 'De la Entidad' : 'De toda la app'),
            for (final s in ownOnly) tile(s),
            if (defaults.isNotEmpty) ...[
              const SectionTitle('Valores por defecto de los ajustes de cada usuario'),
              for (final s in defaults) tile(s),
            ],
          ]);
        },
      ),
    );
  }
}
