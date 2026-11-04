import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/user_settings.dart';
import '../navigation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'setting_editor.dart';

/// Ajustes de un nivel concreto (docs/11 §11.17): de un trabajador
/// (settings.worker), de un itinerario o de una parada dentro de un
/// itinerario (settings.itinerary). Gana el más concreto: trabajador →
/// parada del itinerario → itinerario → Entidad → app. Cada fila muestra el
/// valor que rige y, si es propio de este nivel, el que heredaría; tocarla lo
/// cambia y «Volver al heredado» quita el propio.
class ScopedSettingsScreen extends StatefulWidget {
  final String title;

  /// Ruta de la colección y de cada ajuste (`<path>/<clave>`).
  final String path;

  /// filter[...] que identifica el nivel (se añade también al cambiar un ajuste).
  final Map<String, String> filter;
  final String type;

  /// «Propio del trabajador», «Propio del itinerario»…
  final String customLabel;

  // ignore: prefer_const_constructors_in_immutables
  ScopedSettingsScreen.worker({super.key, required String userId, required String name})
      : title = 'Ajustes de $name',
        path = '/users/$userId/settings',
        filter = const {},
        type = 'user-settings',
        customLabel = 'Propio del trabajador';

  ScopedSettingsScreen.itinerary({super.key, required String itineraryId, required String name})
      : title = 'Ajustes de $name',
        path = '/itinerary-settings',
        filter = {'filter[itinerary]': itineraryId},
        type = 'itinerary-settings',
        customLabel = 'Propio del itinerario';

  /// [itineraryStopId] es el id de `itinerary-stops` (la parada dentro del itinerario).
  ScopedSettingsScreen.stop({super.key, required String itineraryStopId, required String name})
      : title = 'Ajustes de la parada $name',
        path = '/itinerary-stop-settings',
        filter = {'filter[itineraryStop]': itineraryStopId},
        type = 'itinerary-stop-settings',
        customLabel = 'Propio de la parada';

  @override
  State<ScopedSettingsScreen> createState() => _ScopedSettingsScreenState();
}

class _ScopedSettingsScreenState extends State<ScopedSettingsScreen> {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, List<Resource>)>>();

  String get _query => widget.filter.isEmpty ? '' : '?${widget.filter.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';

  Future<(Map<String, SettingDefinition>, List<Resource>)> _load() async {
    final api = context.api;
    final settings = (await api.get(widget.path, query: widget.filter)).resources;
    return (await loadSettingDefinitions(api), settings);
  }

  Future<void> _edit(SettingDefinition definition, String current) async {
    final value = await editSettingValue(context, definition, current);
    if (value == null || !mounted) return;
    await runAction(context, () => context.api.patch('${widget.path}/${definition.key}$_query', {
          'data': {'type': widget.type, 'id': definition.key, 'attributes': {'value': value}},
        }));
    _view.currentState?.reload();
  }

  Future<void> _reset(SettingDefinition definition) async {
    await runAction(context, () => context.api.delete('${widget.path}/${definition.key}$_query'), success: 'Se usa el valor heredado.');
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.title,
      tab: MainTab.more,
      body: AsyncView<(Map<String, SettingDefinition>, List<Resource>)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final (definitions, settings) = data;
          final rows = settings.where((s) => definitions[s.id] != null).toList();
          if (rows.isEmpty) return const EmptyView(icon: Icons.tune, message: 'No hay ajustes en este nivel.');
          final small = Theme.of(context).textTheme.bodySmall;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Gana el más concreto: trabajador → parada → itinerario → Entidad → app.'),
            ),
            for (final s in rows)
              Builder(builder: (context) {
                final definition = definitions[s.id]!;
                final value = s.string('value') ?? '';
                final custom = s.boolean('isCustom');
                final editable = s.attributes['editable'] != false;
                return BusyListTile(
                  title: Text(definition.name),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((definition.description ?? '').isNotEmpty) Text(definition.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                    Text(describeSetting(definition, value), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (custom)
                      Text('${widget.customLabel} (heredado: ${describeSetting(definition, s.string('inheritedValue') ?? '')})',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                  ]),
                  trailing: custom && editable
                      ? BusyIconButton(tooltip: 'Volver al heredado', icon: const Icon(Icons.undo), onPressed: () => _reset(definition))
                      : null,
                  onTap: editable ? () => _edit(definition, value) : null,
                );
              }),
          ]);
        },
      ),
    );
  }
}
