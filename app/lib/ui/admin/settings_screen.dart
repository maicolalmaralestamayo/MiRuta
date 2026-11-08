import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/app_settings.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

/// Ajustes de la app (docs/11 §11.38, §11.40 y §11.44; maqueta G18 n.º 18):
/// un solo nivel, por grupos, con unidades (`10min`, `1km200m`, `10km/hor`).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _view = GlobalKey<DataViewState<List<Setting>>>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};

  Future<List<Setting>> _load() async {
    final list = (await AppSettings.refresh(context.read<Session>().api)).$2;
    for (final s in list) {
      (_controllers[s.key] ??= TextEditingController()).text = s.value;
    }
    _errors.clear();
    return list;
  }

  Future<void> _save() async {
    final list = _view.currentState?.data ?? const <Setting>[];
    final api = context.read<Session>().api;
    var changed = 0;
    for (final s in list) {
      final value = _controllers[s.key]!.text.trim();
      if (value == s.value) continue;
      try {
        await api.patch('/settings/${s.key}', resourceData('settings', id: s.key, attributes: {'value': value.isEmpty ? null : value}));
        changed++;
        _errors.remove(s.key);
      } on ApiException catch (error) {
        _errors[s.key] = error.message;
      }
    }
    if (!mounted) return;
    setState(() {});
    if (_errors.isNotEmpty) {
      showMessage(context, 'Revise los valores marcados en rojo.');
    } else {
      showMessage(context, changed == 0 ? 'No hay cambios.' : 'Ajustes guardados.');
      await _view.currentState?.reload();
      if (mounted) await context.read<Session>().sync(all: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ajustes de la app',
      tab: MainTab.more,
      actions: () => [ActionItem(Icons.save_outlined, 'Guardar cambios', _save)],
      body: DataView<List<Setting>>(
        key: _view,
        load: _load,
        builder: (context, list, reload) {
          final groups = <String, List<Setting>>{};
          for (final s in list) {
            groups.putIfAbsent(s.groupName.isEmpty ? s.group : s.groupName, () => []).add(s);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
            for (final entry in groups.entries)
              FoldSection<Setting>(
                storageKey: 'ajustes.${entry.key}',
                title: entry.key,
                items: entry.value,
                paginate: false,
                initiallyOpen: entry.key == groups.keys.first,
                builder: (s) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: TextField(
                    controller: _controllers[s.key],
                    decoration: InputDecoration(
                      labelText: s.name,
                      helperText: s.description,
                      helperMaxLines: 3,
                      hintText: s.defaultValue,
                      errorText: _errors[s.key],
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tiempos: seg, min, hor, dia, sem, mes (30 días), ano (365 días), combinables (12hor30min). Distancias: m, km (1km200m). '
                  'Velocidades: distancia/tiempo (10km/hor). Vacío = valor por omisión.'),
            ),
          ]);
        },
      ),
    );
  }
}
