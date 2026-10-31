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
  bool _showInactive = false;

  Future<List<Entity>> _load() async => (await context.api.getAll('/entities', query: {
        'sort': 'abbreviation',
        'filter[active]': _showInactive ? 'all' : 'true',
      }))
          .map(Entity.from)
          .toList();

  Future<void> _edit(Entity? entity) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EntityFormScreen(entity: entity)));
    if (saved == true) _view.currentState?.reload();
  }

  Future<void> _toggle(Entity entity) async {
    if (entity.active &&
        !await confirm(context, 'Desactivar ${entity.abbreviation}', 'Sus trabajadores no podrán unirse a ella mientras esté inactiva.', accept: 'Desactivar', destructive: true)) {
      return;
    }
    if (!mounted) return;
    await context.api.patch('/entities/${entity.id}', resourceData('entities', id: entity.id, attributes: {'active': !entity.active}));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entidades'), actions: [
        IconButton(
          tooltip: _showInactive ? 'Ocultar inactivas' : 'Ver inactivas',
          icon: Icon(_showInactive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () {
            setState(() => _showInactive = !_showInactive);
            _view.currentState?.reload();
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(null), child: const Icon(Icons.add)),
      body: AsyncView<List<Entity>>(
        key: _view,
        load: _load,
        builder: (context, entities, reload) => entities.isEmpty
            ? const EmptyView(icon: Icons.apartment_outlined, message: 'Todavía no hay Entidades. Crea la primera para que los trabajadores puedan unirse.')
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final entity in entities)
                  ListTile(
                    leading: CircleAvatar(child: Text(entity.abbreviation.isEmpty ? '?' : entity.abbreviation[0])),
                    title: Text(entity.abbreviation, style: TextStyle(decoration: entity.active ? null : TextDecoration.lineThrough)),
                    subtitle: Text([entity.name, if (entity.number != null) 'Nº ${entity.number}', if (!entity.active) 'Inactiva'].join(' · ')),
                    onTap: () => _edit(entity),
                    trailing: BusyIconButton(
                      tooltip: entity.active ? 'Desactivar' : 'Reactivar',
                      icon: Icon(entity.active ? Icons.block : Icons.restore),
                      onPressed: () => _toggle(entity),
                    ),
                  ),
              ]),
      ),
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
  ApiException? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    final entity = widget.entity;
    final body = resourceData('entities', id: entity?.id, attributes: {
      'abbreviation': _abbreviation.text.trim().toUpperCase(),
      'number': _number.text.trim().isEmpty ? null : _number.text.trim(),
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'observation': _observation.text.trim().isEmpty ? null : _observation.text.trim(),
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
            decoration: InputDecoration(
              labelText: 'Abreviatura',
              helperText: 'Es lo que se muestra en toda la app y lo que escriben los trabajadores para unirse. De 2 a 15 letras y números.',
              helperMaxLines: 3,
              errorText: _error?.fieldError('/abbreviation'),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(15)],
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'De 2 a 15 letras y números' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _number,
            decoration: InputDecoration(labelText: 'Número (opcional)', helperText: '4 dígitos', errorText: _error?.fieldError('/number')),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            validator: (v) => (v ?? '').isEmpty || v!.length == 4 ? null : 'Tiene que tener 4 dígitos',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe el nombre' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Descripción (opcional)'), maxLines: 3),
          const SizedBox(height: 12),
          TextFormField(controller: _observation, decoration: const InputDecoration(labelText: 'Observación (opcional)'), maxLines: 3),
          if (_error != null && _error!.fieldError('/abbreviation') == null && _error!.fieldError('/number') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, child: const Text('Guardar')),
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
      subtitle: const Text('Entidad con la que trabajas'),
      trailing: const Icon(Icons.swap_horiz),
      onTap: _pick,
    );
  }
}
