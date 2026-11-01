import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Entidades (solo el Administrador, docs/08-version-2.md §8.2): abreviatura
/// (obligatoria y única), número (opcional), nombre y campos de nomenclador.
class EntitiesScreen extends StatefulWidget {
  const EntitiesScreen({super.key});

  @override
  State<EntitiesScreen> createState() => _EntitiesScreenState();
}

class _EntitiesScreenState extends State<EntitiesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Entity>>>();

  /// Filtro de la lista: 'true' (activadas), 'false' (desactivadas) o 'all'.
  String _filter = 'true';

  Future<List<Entity>> _load() async => (await context.api.getAll('/entities', query: {
        'sort': 'abbreviation',
        'filter[active]': _filter == 'false' ? 'all' : _filter,
      }))
          .map(Entity.from)
          .where((e) => _filter != 'false' || !e.active)
          .toList();

  Future<void> _edit(Entity? entity) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EntityFormScreen(entity: entity)));
    if (saved == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entidades')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Nueva Entidad')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: DropdownButtonFormField<String>(
            initialValue: _filter,
            decoration: const InputDecoration(labelText: 'Mostrar', isDense: true),
            items: const [
              DropdownMenuItem(value: 'true', child: Text('Activadas')),
              DropdownMenuItem(value: 'false', child: Text('Desactivadas')),
              DropdownMenuItem(value: 'all', child: Text('Todas')),
            ],
            onChanged: (value) {
              setState(() => _filter = value!);
              _view.currentState?.reload();
            },
          ),
        ),
        Expanded(
          child: AsyncView<List<Entity>>(
            key: _view,
            load: _load,
            builder: (context, entities, reload) => entities.isEmpty
                ? const EmptyView(icon: Icons.apartment_outlined, message: 'No hay Entidades que mostrar.')
                : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                    for (final entity in entities)
                      ListTile(
                        leading: CircleAvatar(child: Text(entity.abbreviation.isEmpty ? '?' : entity.abbreviation[0])),
                        title: Text(entity.abbreviation, style: TextStyle(decoration: entity.active ? null : TextDecoration.lineThrough)),
                        subtitle: Text([entity.name, if (entity.number != null) 'Nº ${entity.number}', if (!entity.active) 'Desactivada'].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _edit(entity),
                      ),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class EntityFormScreen extends StatefulWidget {
  final Entity? entity;

  const EntityFormScreen({super.key, this.entity});

  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _abbreviation = TextEditingController(text: widget.entity?.abbreviation);
  late final _number = TextEditingController(text: widget.entity?.number);
  late final _name = TextEditingController(text: widget.entity?.name);
  late final _description = TextEditingController(text: widget.entity?.description);
  late final _observation = TextEditingController(text: widget.entity?.observation);
  late bool _active = widget.entity?.active ?? true;
  ApiException? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    final entity = widget.entity;
    if (entity != null && entity.active && !_active &&
        !await confirm(context, 'Desactivar ${entity.abbreviation}', 'Sus trabajadores no podrán unirse a ella mientras esté desactivada.', accept: 'Desactivar', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final body = resourceData('entities', id: entity?.id, attributes: {
      'abbreviation': _abbreviation.text.trim().toUpperCase(),
      'number': _number.text.trim().isEmpty ? null : _number.text.trim(),
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'observation': _observation.text.trim().isEmpty ? null : _observation.text.trim(),
      if (entity != null && entity.active != _active) 'active': _active,
    });
    try {
      entity == null ? await context.api.post('/entities', body) : await context.api.patch('/entities/${entity.id}', body);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entity == null ? 'Nueva Entidad' : widget.entity!.abbreviation)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _abbreviation,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(labelText: 'Abreviatura', hintText: 'p. ej. EMPRESA1', errorText: _error?.fieldError('/abbreviation')),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(15)],
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Escriba de 2 a 15 letras y números.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _number,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(labelText: 'Número (opcional)', hintText: 'p. ej. 0123', errorText: _error?.fieldError('/number')),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            validator: (v) => (v ?? '').isEmpty || v!.length == 4 ? null : 'Escriba 4 dígitos.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'p. ej. Empresa de Servicios'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escriba el nombre.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Descripción (opcional)'), maxLines: 3),
          const SizedBox(height: 12),
          TextFormField(controller: _observation, decoration: const InputDecoration(labelText: 'Observación (opcional)'), maxLines: 3),
          if (widget.entity != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _active,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Activada')),
                DropdownMenuItem(value: false, child: Text('Desactivada')),
              ],
              onChanged: (value) => setState(() => _active = value!),
            ),
          ],
          if (_error != null && _error!.fieldError('/abbreviation') == null && _error!.fieldError('/number') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, icon: const Icon(Icons.save), child: const Text('Guardar Entidad')),
        ]),
      ),
    );
  }
}

/// Selector de la Entidad con la que trabaja el Administrador en la gestión
/// (null = todas). Al crear itinerarios, paradas, vehículos o trabajadores
/// tiene que haber una elegida.
class AdminEntitySelector extends StatefulWidget {
  final VoidCallback? onChanged;

  const AdminEntitySelector({super.key, this.onChanged});

  @override
  State<AdminEntitySelector> createState() => _AdminEntitySelectorState();
}

class _AdminEntitySelectorState extends State<AdminEntitySelector> {
  Future<void> _pick() async {
    final entities = (await context.api.getAll('/entities', query: {'sort': 'abbreviation'})).map(Entity.from).toList();
    if (!mounted) return;
    final all = Entity(id: '', abbreviation: 'Todas', name: 'Ver todas las Entidades');
    final picked = await pickFrom<Entity>(context, 'Entidad', [all, ...entities], (e) => e.abbreviation, subtitle: (e) => e.name);
    if (picked == null || !mounted) return;
    setState(() => context.session.adminEntity = picked.id.isEmpty ? null : picked);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final entity = context.session.adminEntity;
    return BusyListTile(
      leading: const Icon(Icons.apartment_outlined),
      title: Text(entity == null ? 'Todas las Entidades' : '${entity.abbreviation} · ${entity.name}'),
      subtitle: const Text('Entidad con la que trabaja'),
      trailing: const Icon(Icons.swap_horiz),
      onTap: _pick,
    );
  }
}
