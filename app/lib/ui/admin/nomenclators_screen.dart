import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Nomencladores: denominación, descripción y observación, más los campos
/// propios de las jerarquías (orden de presentación e icono) y de los motivos (destinatario).
class NomenclatorsScreen extends StatefulWidget {
  final String title;
  final String path;
  final String type;
  final String sort;

  const NomenclatorsScreen._(this.title, this.path, this.type, this.sort);

  factory NomenclatorsScreen.vehicleTypes() => const NomenclatorsScreen._('Tipos de vehículo', '/vehicle-types', 'vehicle-types', 'name');

  factory NomenclatorsScreen.absenceTypes() => const NomenclatorsScreen._('Tipos de ausencia', '/absence-types', 'absence-types', 'name');

  factory NomenclatorsScreen.ranks() => const NomenclatorsScreen._('Jerarquías', '/ranks', 'ranks', 'sortOrder,name');

  /// Palabras que no puede contener un usuario (solo el Administrador).
  factory NomenclatorsScreen.forbiddenWords() => const NomenclatorsScreen._('Palabras no permitidas', '/forbidden-words', 'forbidden-words', 'name');

  factory NomenclatorsScreen.conversationTopics() => const NomenclatorsScreen._('Motivos de conversación', '/conversation-topics', 'conversation-topics', 'name');

  @override
  State<NomenclatorsScreen> createState() => _NomenclatorsScreenState();
}

class _NomenclatorsScreenState extends State<NomenclatorsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Named>>>();

  bool get _isRank => widget.type == 'ranks';

  bool get _isTopic => widget.type == 'conversation-topics';

  Future<List<Named>> _load() async => (await context.api.getAll(widget.path, query: {'sort': widget.sort})).map(Named.from).toList();

  Future<void> _edit(Named? item) async {
    final name = await promptText(context, 'Denominación', initial: item?.name ?? '', required: true);
    if (name == null || !mounted) return;
    final description = await promptText(context, 'Descripción (opcional)', initial: item?.description ?? '', maxLines: 3);
    if (description == null || !mounted) return;
    final observation = await promptText(context, 'Observación (opcional)', initial: item?.observation ?? '', maxLines: 3);
    if (observation == null || !mounted) return;
    final attributes = <String, dynamic>{'name': name, 'description': description.isEmpty ? null : description, 'observation': observation.isEmpty ? null : observation};

    if (_isRank) {
      final order = await promptText(context, 'Orden en las listas', initial: '${item?.extra['sortOrder'] ?? ''}');
      if (order == null || !mounted) return;
      attributes['sortOrder'] = int.tryParse(order) ?? 0;
    }
    if (_isTopic) {
      final recipient = await pickFrom<String>(context, 'Destinatario', ['itinerary_chiefs', 'transport_chiefs', 'developer'], Conversation.recipientLabel);
      if (recipient == null || !mounted) return;
      attributes['recipient'] = recipient;
    }

    final body = resourceData(widget.type, id: item?.id, attributes: attributes);
    await runAction(context, () => item == null ? context.api.post(widget.path, body) : context.api.patch('${widget.path}/${item.id}', body));
    _view.currentState?.reload();
  }

  Future<void> _delete(Named item) async {
    if (!await confirm(context, 'Borrar', '¿Borrar "${item.name}"?', destructive: true) || !mounted) return;
    await runAction(context, () => context.api.delete('${widget.path}/${item.id}'));
    _view.currentState?.reload();
  }

  Future<void> _icon(Named item) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256);
    if (file == null || !mounted) return;
    await runAction(context, () => context.api.upload('/ranks/${item.id}/icon', 'icon', file.path), success: 'Icono actualizado');
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(null), child: const Icon(Icons.add)),
      body: AsyncView<List<Named>>(
        key: _view,
        load: _load,
        builder: (context, items, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final item in items)
            ListTile(
              leading: _isRank
                  ? GestureDetector(
                      onTap: () => _icon(item),
                      child: item.extra['iconUrl'] == null
                          ? CircleAvatar(child: Text('${item.extra['sortOrder']}'))
                          : CircleAvatar(backgroundImage: NetworkImage('${item.extra['iconUrl']}')),
                    )
                  : null,
              title: Text(item.name),
              subtitle: Text([
                if (_isTopic) Conversation.recipientLabel('${item.extra['recipient']}'),
                if (item.description != null) item.description!,
              ].join(' · ')),
              onTap: () => _edit(item),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(item)),
            ),
          if (_isRank) const Padding(padding: EdgeInsets.all(16), child: Text('Toca el círculo de una jerarquía para subir su icono.')),
        ]),
      ),
    );
  }
}
