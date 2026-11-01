import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Nomencladores: denominación, descripción y observación, más los campos
/// propios de las jerarquías (orden de presentación e icono) y de los motivos
/// (destinatario). Todo en un solo formulario (docs/09 §32).
class NomenclatorsScreen extends StatefulWidget {
  final String title;
  final String path;
  final String type;
  final String sort;

  /// Nombre de un elemento, para los botones ("Guardar tipo de vehículo").
  final String singular;

  /// Hint de ejemplo de la denominación.
  final String example;

  const NomenclatorsScreen._(this.title, this.path, this.type, this.sort, this.singular, this.example);

  factory NomenclatorsScreen.vehicleTypes() =>
      const NomenclatorsScreen._('Tipos de vehículo', '/vehicle-types', 'vehicle-types', 'name', 'tipo de vehículo', 'p. ej. Ómnibus');

  factory NomenclatorsScreen.absenceTypes() =>
      const NomenclatorsScreen._('Tipos de ausencia', '/absence-types', 'absence-types', 'name', 'tipo de ausencia', 'p. ej. Vacaciones');

  factory NomenclatorsScreen.ranks() => const NomenclatorsScreen._('Jerarquías', '/ranks', 'ranks', 'sortOrder,name', 'jerarquía', 'p. ej. Especialista');

  factory NomenclatorsScreen.conversationTopics() =>
      const NomenclatorsScreen._('Motivos de conversación', '/conversation-topics', 'conversation-topics', 'name', 'motivo', 'p. ej. Cambio de parada');

  @override
  State<NomenclatorsScreen> createState() => _NomenclatorsScreenState();
}

class _NomenclatorsScreenState extends State<NomenclatorsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Named>>>();

  bool get _isRank => widget.type == 'ranks';

  bool get _isTopic => widget.type == 'conversation-topics';

  Future<List<Named>> _load() async => (await context.api.getAll(widget.path, query: {'sort': widget.sort})).map(Named.from).toList();

  Future<void> _edit(Named? item) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _NomenclatorForm(screen: widget, item: item)));
    if (saved == true) _view.currentState?.reload();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text('Nuevo ${widget.singular}'.replaceFirst('Nuevo jerarquía', 'Nueva jerarquía')),
      ),
      body: AsyncView<List<Named>>(
        key: _view,
        load: _load,
        builder: (context, items, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final item in items)
            ListTile(
              leading: _isRank
                  ? IconButton(
                      tooltip: 'Cambiar el icono',
                      onPressed: () => _icon(item),
                      icon: item.extra['iconUrl'] == null
                          ? const Icon(rankIcon)
                          : Image.network('${item.extra['iconUrl']}', width: 24, height: 24, errorBuilder: (_, _, _) => const Icon(rankIcon)),
                    )
                  : null,
              title: Text(item.name),
              subtitle: Text([
                if (_isRank) 'Orden ${item.extra['sortOrder'] ?? 0}',
                if (_isTopic) Conversation.recipientLabel('${item.extra['recipient']}'),
                if (item.description != null) item.description!,
              ].join(' · ')),
              onTap: () => _edit(item),
              trailing: DeleteButton(
                what: '"${item.name}"',
                onDelete: () async {
                  await runAction(context, () => context.api.delete('${widget.path}/${item.id}'));
                  _view.currentState?.reload();
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _NomenclatorForm extends StatefulWidget {
  final NomenclatorsScreen screen;
  final Named? item;

  const _NomenclatorForm({required this.screen, this.item});

  @override
  State<_NomenclatorForm> createState() => _NomenclatorFormState();
}

class _NomenclatorFormState extends State<_NomenclatorForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _description = TextEditingController(text: widget.item?.description);
  late final _observation = TextEditingController(text: widget.item?.observation);
  late final _order = TextEditingController(text: widget.item == null ? '' : '${widget.item!.extra['sortOrder'] ?? 0}');
  late String? _recipient = widget.item?.extra['recipient'] as String?;

  bool get _isRank => widget.screen.type == 'ranks';

  bool get _isTopic => widget.screen.type == 'conversation-topics';

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final item = widget.item;
    final screen = widget.screen;
    final body = resourceData(screen.type, id: item?.id, attributes: {
      'name': _name.text.trim(),
      'description': _optional(_description),
      'observation': _optional(_observation),
      if (_isRank) 'sortOrder': int.tryParse(_order.text.trim()) ?? 0,
      if (_isTopic) 'recipient': _recipient,
    });
    await (item == null ? context.api.post(screen.path, body) : context.api.patch('${screen.path}/${item.id}', body));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final singular = widget.screen.singular;
    final feminine = singular == 'jerarquía';
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? (feminine ? 'Nueva $singular' : 'Nuevo $singular') : widget.item!.name)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(labelText: 'Denominación', hintText: widget.screen.example),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Escriba la denominación.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _observation,
            decoration: const InputDecoration(labelText: 'Observación (opcional)'),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
          ),
          if (_isRank) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _order,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Orden en las listas', hintText: 'p. ej. 1'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Escriba un número entero.' : null,
            ),
          ],
          if (_isTopic) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recipient,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Destinatario'),
              items: [
                for (final r in const ['itinerary_chiefs', 'transport_chiefs', 'developer']) DropdownMenuItem(value: r, child: Text(Conversation.recipientLabel(r))),
              ],
              onChanged: (value) => setState(() => _recipient = value),
              validator: (v) => v == null ? 'Elija el destinatario.' : null,
            ),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, icon: const Icon(Icons.save), child: Text('Guardar $singular')),
        ]),
      ),
    );
  }
}
