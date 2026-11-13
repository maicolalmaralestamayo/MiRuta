import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/app_updates.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/busy.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import '../widgets/marks.dart';

/// Actualizaciones de la app (docs/11 §11.54, maqueta G18 n.º 20): el
/// Administrador sube los APK de 64 y 32 bits y marca la versión Obligatoria
/// u Opcional.
class AppVersionsScreen extends StatefulWidget {
  const AppVersionsScreen({super.key});

  @override
  State<AppVersionsScreen> createState() => _AppVersionsScreenState();
}

class _AppVersionsScreenState extends State<AppVersionsScreen> {
  final _view = GlobalKey<DataViewState<(List<AppVersion>, int)>>();
  final _marks = Marks();

  Future<(List<AppVersion>, int)> _load() async {
    final list = (await context.read<Session>().api.get('/app-versions')).resources.map(AppVersion.from).toList();
    return (list, await AppUpdates.currentVersionCode());
  }

  Future<void> _toggleMandatory(AppVersion v) async {
    await context.read<Session>().api.patch('/app-versions/${v.id}', resourceData('app-versions', id: v.id, attributes: {'mandatory': !v.mandatory}));
    _marks.clear();
    _view.currentState?.reload();
  }

  List<ActionItem> _actions() {
    final list = _view.currentState?.data?.$1 ?? const <AppVersion>[];
    if (!_marks.active) {
      return [
        ActionItem(Icons.upload, 'Publicar versión', () async {
          await push(context, const _PublishScreen());
          _view.currentState?.reload();
        }),
      ];
    }
    final marked = _marks.of('version', list, (v) => v.id);
    return [
      ...markActions(_marks, list.map((v) => v.id)),
      if (marked.length == 1) ActionItem(marked.first.mandatory ? Icons.toggle_off_outlined : Icons.priority_high, marked.first.mandatory ? 'Hacer opcional' : 'Hacer obligatoria', () => _toggleMandatory(marked.first)),
      ActionItem(Icons.delete_outline, 'Retirar', () async {
        if (!await confirmDelete(context, marked.length == 1 ? 'la versión ${marked.first.versionName}' : '${marked.length} versiones', consequences: 'Se borran sus APK del servidor.')) return;
        if (!mounted) return;
        final api = context.read<Session>().api;
        for (final v in marked) {
          await api.delete('/app-versions/${v.id}');
        }
        _marks.clear();
        _view.currentState?.reload();
      }, destructive: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Actualizaciones de la app',
      tab: MainTab.more,
      marks: _marks,
      actions: _actions,
      body: DataView<(List<AppVersion>, int)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final cards = <(AppVersion, Map<String, dynamic>?)>[for (final v in data.$1) if (v.files.isEmpty) (v, null) else for (final f in v.files) (v, f)];
          return ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
            FoldSection<(AppVersion, Map<String, dynamic>?)>(
              storageKey: 'versiones',
              title: 'Versiones',
              total: data.$1.length,
              items: cards,
              emptyText: 'Aún no hay versiones publicadas. Use Acciones → Publicar versión.',
              builder: (item) {
                final (v, f) = item;
                final abi = f?['abi'];
                final bits = abi == 'arm64-v8a' ? '64 bits' : (abi == 'armeabi-v7a' ? '32 bits' : 'Universal');
                return ListenableBuilder(
                  listenable: _marks,
                  builder: (context, _) => InfoCard(
                    images: const [CardImage(icon: Icons.system_update_alt)],
                    title: v.versionName,
                    chip: v.versionCode == data.$2 ? const Chip2('Actual', green) : (v.mandatory ? const Chip2('Obligatoria', red) : null),
                    lines: [
                      '${f == null ? '' : '$bits • ${sizeLabel((f['sizeBytes'] as num?)?.toInt() ?? 0)} • '}${v.mandatory ? 'Obligatoria' : 'Opcional'}',
                      'Publicada ${formatDate(v.publishedAt)} • ${plural(v.installedCount, 'persona la tiene', 'personas la tienen')}',
                    ],
                    selected: _marks.isMarked('version', v.id),
                    onTap: () => _marks.toggle('version', v.id),
                    onLongPress: () => _marks.toggle('version', v.id),
                  ),
                );
              },
            ),
          ]);
        },
      ),
    );
  }
}

class _PublishScreen extends StatefulWidget {
  const _PublishScreen();

  @override
  State<_PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<_PublishScreen> {
  final _notes = TextEditingController();
  bool _mandatory = false;
  final Map<String, (String, String)> _files = {};
  double? _progress;
  String? _error;
  bool _published = false;

  Future<void> _pick(String field) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['apk']);
    if (files.isEmpty) return;
    final file = files.first;
    // Se copia a un archivo temporal: Android puede entregarlo sin ruta directa.
    final copy = '${(await getTemporaryDirectory()).path}/$field-${file.name}';
    await file.xFile.saveTo(copy);
    setState(() => _files[field] = (copy, file.name));
  }

  Future<void> _publish() async {
    if (_files.isEmpty) {
      setState(() => _error = 'Elija al menos un APK.');
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await context.read<Session>().api.uploadFiles('/app-versions', {for (final e in _files.entries) e.key: e.value.$1}, fields: {
        'notes': _notes.text.trim(),
        'mandatory': _mandatory ? '1' : '0',
      }, onProgress: (sent, total) => setState(() => _progress = total > 0 ? sent / total : null));
      for (final f in _files.values) {
        await File(f.$1).delete().catchError((_) => File(f.$1));
      }
      _published = true;
      if (mounted) {
        showResult(ScaffoldMessenger.of(context), 'Versión publicada');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      setState(() {
        _progress = null;
        _error = error.message;
      });
    }
  }

  Widget _apk(String field, String label) => InfoCard(
        images: const [CardImage(icon: Icons.android)],
        title: label,
        lines: [_files[field]?.$2 ?? 'Toque para elegir el APK'],
        onTap: _progress == null ? () => _pick(field) : null,
      );

  @override
  Widget build(BuildContext context) {
    return LeaveGuard(
      dirty: () => _progress == null && !_published && (_files.isNotEmpty || _notes.text.trim().isNotEmpty),
      child: AppScaffold.list(
      title: 'Publicar versión',
      tab: MainTab.more,
      actions: () => [if (_progress == null) ActionItem(Icons.upload, 'Publicar', _publish)],
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('La versión y su código se leen del APK. Suba los dos: 64 y 32 bits.')),
        _apk('apkArm64', 'APK de 64 bits'),
        _apk('apkArm32', 'APK de 32 bits'),
        FormText(controller: _notes, label: 'Novedades', maxLines: 3, last: true),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: _mandatory,
          onChanged: _progress == null ? (v) => setState(() => _mandatory = v) : null,
          title: const Text('Obligatoria'),
          subtitle: const Text('Las versiones anteriores tendrán que instalarla para seguir usando la app.'),
        ),
        if (_progress != null) Padding(padding: const EdgeInsets.all(16), child: LinearProgressIndicator(value: _progress)),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: red))),
      ],
    ),
    );
  }
}
