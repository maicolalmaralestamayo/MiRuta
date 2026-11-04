import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../services/templates.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Versiones de la app publicadas (solo el Administrador): publicar un APK,
/// ver cuántos trabajadores tienen cada versión y retirar versiones.
class AppVersionsScreen extends StatefulWidget {
  const AppVersionsScreen({super.key});

  @override
  State<AppVersionsScreen> createState() => _AppVersionsScreenState();
}

class _AppVersionsScreenState extends State<AppVersionsScreen> {
  final _view = GlobalKey<AsyncViewState<JsonApiDocument>>();

  Future<JsonApiDocument> _load() => context.api.get('/app-versions');

  Future<void> _withdraw(Resource version) async {
    await runAction(context, () => context.api.delete('/app-versions/${version.id}'));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Actualizaciones de la app',
      tab: MainTab.more,
      actions: [
        ActionItem(
          icon: Icons.upload,
          label: 'Publicar versión',
          onPressed: () async {
            final published = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _PublishScreen()));
            if (published == true) _view.currentState?.reload();
          },
        ),
      ],
      body: AsyncView<JsonApiDocument>(
        key: _view,
        load: _load,
        builder: (context, document, reload) => ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(plural((document.meta['usersWithoutVersion'] as num? ?? 0).toInt(), 'cuenta sin versión registrada', 'cuentas sin versión registrada')),
          ),
          if (document.resources.isEmpty) const ListTile(title: Text('Aún no se ha publicado ninguna versión.')),
          for (final v in document.resources)
            ListTile(
              leading: CircleAvatar(child: Text('${v.integer('versionCode')}')),
              title: Text('Versión ${v.string('versionName')} (código ${v.integer('versionCode')}) · ${v.boolean('mandatory') ? 'Obligatoria' : 'Opcional'}'),
              subtitle: Text([
                'Publicada ${formatDateTime(v.date('publishedAt')!)}',
                for (final file in (v.attributes['files'] as List? ?? const []).cast<Map>())
                  '${_abiLabel(file['abi'] as String?)}: ${(((file['sizeBytes'] as num?) ?? 0) / (1024 * 1024)).toStringAsFixed(1)} MB',
                plural((v.meta['installedCount'] as num? ?? 0).toInt(), 'cuenta la tiene instalada', 'cuentas la tienen instalada'),
                if (v.string('notes') != null) v.string('notes')!,
              ].join('\n')),
              isThreeLine: true,
              trailing: DeleteButton(what: 'la versión ${v.string('versionName')} (se dejará de ofrecer y se borrará el archivo)', onDelete: () => _withdraw(v)),
            ),
        ]),
      ),
    );
  }
}

String _abiLabel(String? abi) => const {'arm64-v8a': '64 bits', 'armeabi-v7a': '32 bits', 'universal': 'Universal'}[abi] ?? abi ?? '';

class _PublishScreen extends StatefulWidget {
  const _PublishScreen();

  @override
  State<_PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<_PublishScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  bool _mandatory = false;

  /// Campo del formulario → [ruta, nombre]: apkArm64, apkArm32 y apkUniversal.
  final Map<String, (String, String)> _files = {};
  double? _progress;
  String? _error;

  Future<void> _pick(String field) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['apk']);
    if (files.isEmpty) return;
    final file = files.first;
    // Se copia a un archivo temporal: Android puede entregar el archivo sin ruta directa.
    final copy = '${(await getTemporaryDirectory()).path}/$field-${file.name}';
    await file.xFile.saveTo(copy);
    setState(() => _files[field] = (copy, file.name));
  }

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    if (_files.isEmpty) {
      setState(() => _error = 'Elija al menos un APK.');
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await context.api.uploadFiles('/app-versions', {for (final entry in _files.entries) entry.key: entry.value.$1}, fields: {
        'notes': _notes.text.trim(),
        'mandatory': _mandatory ? '1' : '0',
      }, onProgress: (sent, total) => setState(() => _progress = total > 0 ? sent / total : null));
      for (final entry in _files.values) {
        await File(entry.$1).delete().catchError((_) => File(entry.$1));
      }
      if (mounted) {
        // La versión y el código los lee el servidor del APK.
        showMessage(context, 'Versión publicada');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      setState(() {
        _progress = null;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _progress != null;
    return AppScaffold(
      title: 'Publicar versión',
      tab: MainTab.more,
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final (field, label) in const [('apkArm64', 'APK de 64 bits'), ('apkArm32', 'APK de 32 bits'), ('apkUniversal', 'APK universal (opcional)')])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: uploading ? null : () => _pick(field),
                icon: Icon(_files.containsKey(field) ? Icons.check_circle : Icons.android),
                label: Text(_files.containsKey(field) ? '$label: ${_files[field]!.$2}' : 'Elegir $label', overflow: TextOverflow.ellipsis),
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Novedades', hintText: 'p. ej. Corrección de errores'), maxLines: 5, minLines: 2),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            initialValue: _mandatory,
            decoration: const InputDecoration(labelText: 'Tipo de actualización'),
            items: const [
              DropdownMenuItem(value: false, child: Text('Opcional')),
              DropdownMenuItem(value: true, child: Text('Obligatoria')),
            ],
            onChanged: uploading ? null : (value) => setState(() => _mandatory = value!),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (uploading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 4),
            Text('Subiendo… ${((_progress ?? 0) * 100).toStringAsFixed(0)} %', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: uploading ? null : _publish,
            icon: uploading ? const BusyIndicator() : const Icon(Icons.upload),
            label: const Text('Publicar versión'),
          ),
        ]),
      ),
    );
  }
}
