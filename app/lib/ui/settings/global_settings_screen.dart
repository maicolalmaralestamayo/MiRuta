import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/user_settings.dart';
import '../admin/management.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'setting_editor.dart';

/// Ajustes de la app (settings.app) y de una Entidad (settings.entity), con
/// la forma común (docs/11 §11.18). Los de la Entidad llevan el selector de
/// Entidad e incluyen los valores por defecto de los ajustes de cada
/// usuario. Los de itinerario, parada y trabajador están en
/// ScopedSettingsScreen.
class GlobalSettingsScreen extends StatefulWidget {
  final bool entityLevel;

  /// Entidad con la que empezar (por defecto, la última elegida en Gestión).
  final Entity? entity;

  const GlobalSettingsScreen.app({super.key})
      : entityLevel = false,
        entity = null;

  const GlobalSettingsScreen.entity({super.key, this.entity}) : entityLevel = true;

  @override
  State<GlobalSettingsScreen> createState() => _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends State<GlobalSettingsScreen> with ManagementEntityState {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, List<Resource>)>>();

  @override
  String get entityOperation => Op.settingsEntity;

  @override
  void initState() {
    super.initState();
    if (widget.entityLevel) {
      if (widget.entity != null) {
        entity = widget.entity;
        entityResolved = true;
      } else {
        initEntity();
      }
    }
  }

  @override
  void onEntityChanged() => _view.currentState?.reload();

  String get _path => widget.entityLevel ? '/entity-settings' : '/settings';

  Map<String, dynamic> get _filter => widget.entityLevel ? {'filter[entity]': entity!.id} : const {};

  String get _suffix => widget.entityLevel ? '?filter[entity]=${entity!.id}' : '';

  Future<(Map<String, SettingDefinition>, List<Resource>)> _load() async {
    final api = context.api;
    final settings = (await api.get(_path, query: _filter)).resources;
    return (await loadSettingDefinitions(api), settings);
  }

  Future<void> _edit(SettingDefinition definition, String current) async {
    final value = await editSettingValue(context, definition, current);
    if (value == null || !mounted) return;
    await runAction(context, () => context.api.patch('$_path/${definition.key}$_suffix', {
          'data': {'type': widget.entityLevel ? 'entity-settings' : 'settings', 'id': definition.key, 'attributes': {'value': value}},
        }));
    _view.currentState?.reload();
  }

  Future<void> _reset(SettingDefinition definition) async {
    await runAction(context, () => context.api.delete('$_path/${definition.key}$_suffix'));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.entityLevel ? entityPlaceholder() : null;
    return AppScaffold(
      title: widget.entityLevel ? 'Ajustes de la Entidad' : 'Ajustes de la app',
      tab: MainTab.more,
      body: placeholder ?? AsyncView<(Map<String, SettingDefinition>, List<Resource>)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final (definitions, settings) = data;
          final rows = settings.where((s) => definitions[s.id] != null && (widget.entityLevel || s.boolean('editable'))).toList();
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

          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            if (widget.entityLevel) entitySelector(),
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
