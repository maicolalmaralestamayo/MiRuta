import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/roles_api.dart';
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

  factory NomenclatorsScreen.conversationTopics() =>
      const NomenclatorsScreen._('Motivos de conversación', '/conversation-topics', 'conversation-topics', 'name', 'motivo', 'p. ej. Cambio de parada');

  @override
  State<NomenclatorsScreen> createState() => _NomenclatorsScreenState();
}

class _NomenclatorsScreenState extends State<NomenclatorsScreen> {
  final _view = GlobalKey<AsyncViewState<List<Named>>>();

  bool get _isTopic => widget.type == 'conversation-topics';

  Future<List<Named>> _load() async => (await context.api.getAll(widget.path, query: {'sort': widget.sort})).map(Named.from).toList();

  Future<void> _edit(Named? item) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _NomenclatorForm(screen: widget, item: item)));
    if (saved == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text('Nuevo ${widget.singular}'),
      ),
      body: AsyncView<List<Named>>(
        key: _view,
        load: _load,
        builder: (context, items, reload) => ListView(padding: const EdgeInsets.only(bottom: 88), children: [
          for (final item in items)
            ListTile(
              title: Text(item.name),
              subtitle: Text([
                if (_isTopic) item.extra['recipient'] == 'developer' ? 'Desarrollador' : '${item.extra['roleName'] ?? 'Rol'}',
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
  /// 'developer' o el id del rol al que va dirigido (docs/04-api.md: recipient role + relación role).
  late String? _recipient = widget.item == null ? null : (widget.item!.extra['recipient'] == 'developer' ? 'developer' : widget.item!.relations['role']);
  List<Role> _roles = [];

  @override
  void initState() {
    super.initState();
    if (_isTopic) {
      RolesApi(context.api).all().then((roles) {
        if (mounted) setState(() => _roles = roles.where((r) => !r.isAdministrator).toList());
      }).catchError((_) {});
    }
  }

  bool get _isTopic => widget.screen.type == 'conversation-topics';

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final item = widget.item;
    final screen = widget.screen;
    final toRole = _isTopic && _recipient != 'developer';
    final body = resourceData(screen.type, id: item?.id, attributes: {
      'name': _name.text.trim(),
      'description': _optional(_description),
      'observation': _optional(_observation),
      if (_isTopic) 'recipient': toRole ? 'role' : 'developer',
    }, relationships: toRole ? {'role': ResourceId('roles', _recipient!)} : null);
    await (item == null ? context.api.post(screen.path, body) : context.api.patch('${screen.path}/${item.id}', body));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final singular = widget.screen.singular;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? 'Nuevo $singular' : widget.item!.name)),
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
          if (_isTopic) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // Los roles llegan después: hasta entonces no se puede mostrar uno.
              key: ValueKey(_roles.length),
              initialValue: _recipient == 'developer' || _roles.any((r) => r.id == _recipient) ? _recipient : null,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(labelText: 'Destinatario'),
              items: [
                for (final role in _roles) DropdownMenuItem(value: role.id, child: Text(role.name)),
                const DropdownMenuItem(value: 'developer', child: Text('Desarrollador')),
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
