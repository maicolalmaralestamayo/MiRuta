import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../services/templates.dart';
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
    if (!await confirm(context, 'Retirar versión', 'Dejará de ofrecerse la versión ${version.string('versionName')} y se borrará el archivo.', destructive: true)) return;
    if (!mounted) return;
    await runAction(context, () => context.api.delete('/app-versions/${version.id}'));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Actualizaciones de la app')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.upload),
        label: const Text('Publicar versión'),
        onPressed: () async {
          // Se propone el código siguiente al de la última versión publicada.
          int? next;
          try {
            final latest = await context.api.get('/app-versions/latest');
            next = latest.resources.isEmpty ? null : (latest.resource.integer('versionCode') ?? 0) + 1;
          } catch (_) {}
          if (!context.mounted) return;
          final published = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _PublishScreen(suggestedCode: next)));
          if (published == true) _view.currentState?.reload();
        },
      ),
      body: AsyncView<JsonApiDocument>(
        key: _view,
        load: _load,
        builder: (context, document, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${document.meta['workersWithoutVersion'] ?? 0} trabajador(es) sin versión registrada'),
            subtitle: const Text('La versión se registra cuando el trabajador usa la app.'),
          ),
          if (document.resources.isEmpty) const ListTile(title: Text('Aún no se ha publicado ninguna versión.')),
          for (final v in document.resources)
            ListTile(
              leading: CircleAvatar(child: Text('${v.integer('versionCode')}')),
              title: Text('${v.string('versionName')}${v.boolean('mandatory') ? ' · obligatoria' : ''}'),
              subtitle: Text([
                'Publicada ${formatDateTime(v.date('publishedAt')!)}',
                '${((v.integer('sizeBytes') ?? 0) / (1024 * 1024)).toStringAsFixed(1)} MB',
                '${v.meta['installedCount'] ?? 0} la tienen instalada',
                if (v.string('notes') != null) v.string('notes')!,
              ].join('\n')),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _withdraw(v)),
            ),
        ]),
      ),
    );
  }
}

class _PublishScreen extends StatefulWidget {
  final int? suggestedCode;

  const _PublishScreen({this.suggestedCode});

  @override
  State<_PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<_PublishScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _notes = TextEditingController();
  bool _mandatory = false;
  String? _filePath;
  String? _fileName;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedCode != null) _code.text = '${widget.suggestedCode}';
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['apk']);
    if (files.isEmpty) return;
    final file = files.first;
    // Se copia a un archivo temporal: Android puede entregar el archivo sin ruta directa.
    final copy = '${(await getTemporaryDirectory()).path}/${file.name}';
    await file.xFile.saveTo(copy);
    setState(() {
      _filePath = copy;
      _fileName = file.name;
    });
  }

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    if (_filePath == null) {
      setState(() => _error = 'Elige el archivo APK.');
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await context.api.upload('/app-versions', 'apk', _filePath!, fields: {
        'versionName': _name.text.trim(),
        'versionCode': _code.text.trim(),
        'notes': _notes.text.trim(),
        'mandatory': _mandatory ? '1' : '0',
      }, onProgress: (sent, total) => setState(() => _progress = total > 0 ? sent / total : null));
      await File(_filePath!).delete().catchError((_) => File(_filePath!));
      if (mounted) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Publicar versión')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          OutlinedButton.icon(onPressed: uploading ? null : _pick, icon: const Icon(Icons.android), label: Text(_fileName ?? 'Elegir el archivo APK')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Versión (p. ej. 1.2.0)', helperText: 'La parte antes del "+" en pubspec.yaml'),
            validator: (v) => v!.trim().isEmpty ? 'Obligatoria' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Código de versión', helperText: 'El número después del "+" en pubspec.yaml; mayor que el anterior'),
            keyboardType: TextInputType.number,
            validator: (v) => int.tryParse(v ?? '') == null ? 'Número entero' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Novedades'), maxLines: 5),
          SwitchListTile(
            title: const Text('Obligatoria'),
            subtitle: const Text('Las versiones anteriores no podrán usarse hasta actualizar'),
            value: _mandatory,
            onChanged: uploading ? null : (value) => setState(() => _mandatory = value),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (uploading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 4),
            Text('Subiendo… ${((_progress ?? 0) * 100).toStringAsFixed(0)} %', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: uploading ? null : _publish, child: const Text('Publicar')),
        ]),
      ),
    );
  }
}
