import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../navigation.dart';
import '../settings/global_settings_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';

/// Entidades (Gestión, docs/11 §11.10 y §11.15): tarjetas de Entidad con su
/// imagen. Crear, editar, desactivar y reactivar (entities.manage).
class EntitiesScreen extends StatefulWidget {
  const EntitiesScreen({super.key});

  @override
  State<EntitiesScreen> createState() => _EntitiesScreenState();
}

class _EntitiesScreenState extends State<EntitiesScreen> {
  final _view = GlobalKey<AsyncViewState<List<Entity>>>();
  final _selection = SelectionController();
  List<Entity> _entities = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<Entity>> _load() async {
    final entities = (await context.api.getAll('/entities', query: {'sort': 'abbreviation', 'filter[active]': 'all'})).map(Entity.from).toList();
    _entities = entities;
    _selection.retain(entities.map((e) => e.id));
    return entities;
  }

  Future<void> _open(Entity? entity) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EntityFormScreen(entity: entity)));
    _view.currentState?.reload();
  }

  Future<void> _setActive(bool active) async {
    final selected = _selection.selectedOf(_entities, (e) => e.id);
    final api = context.api;
    final ok = await runAction(context, () async {
      for (final e in selected) {
        await api.patch('/entities/${e.id}', resourceData('entities', id: e.id, attributes: {'active': active}));
      }
    }, success: active ? 'Reactivadas.' : 'Desactivadas.');
    if (ok) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final manage = context.me.canAnywhere(Op.entitiesManage);
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selected = _selection.selectedOf(_entities, (e) => e.id);
        return AppScaffold(
          title: 'Entidades',
          tab: MainTab.more,
          selection: _selection,
          selectionTitle: (n) => n == 1 ? '1 seleccionada' : '$n seleccionadas',
          actions: [
            ActionItem(icon: Icons.add_business_outlined, label: 'Crear Entidad', enabled: manage, onPressed: () => _open(null)),
            const ActionItem.divider(),
            ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(selected.first)),
            ActionItem(
              icon: Icons.toggle_off_outlined,
              label: 'Desactivar',
              needs: ActionNeeds.some,
              enabled: manage && selected.every((e) => e.active),
              confirmation: 'Sus trabajadores no podrán unirse a ellas mientras estén desactivadas. ¿Desactivarlas?',
              onPressed: () => _setActive(false),
            ),
            ActionItem(
              icon: Icons.toggle_on_outlined,
              label: 'Reactivar',
              needs: ActionNeeds.some,
              enabled: manage && selected.every((e) => !e.active),
              onPressed: () => _setActive(true),
            ),
          ],
          body: AsyncView<List<Entity>>(
            key: _view,
            load: _load,
            builder: (context, entities, reload) => SelectableCardList<Entity>(
              controller: _selection,
              sections: [
                CardSection(title: 'Activas', items: entities.where((e) => e.active).toList()),
                CardSection(title: 'Desactivadas', items: entities.where((e) => !e.active).toList()),
              ],
              emptyText: 'Todavía no hay Entidades.',
              keyOf: (e) => e.id,
              onOpen: _open,
              cardBuilder: (context, e, selected, onTap, onLongPress) => Opacity(
                opacity: e.active ? 1 : 0.55,
                child: EntityCard(e, selected: selected, onTap: onTap, onLongPress: onLongPress),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Crear o editar una Entidad: imagen, abreviatura (única), número, nombre,
/// descripción y observación.
class EntityFormScreen extends StatefulWidget {
  final Entity? entity;

  const EntityFormScreen({super.key, this.entity});

  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  final _form = GlobalKey<FormState>();
  late Entity? _entity = widget.entity;
  late final _abbreviation = TextEditingController(text: _entity?.abbreviation);
  late final _number = TextEditingController(text: _entity?.number);
  late final _name = TextEditingController(text: _entity?.name);
  late final _description = TextEditingController(text: _entity?.description);
  late final _observation = TextEditingController(text: _entity?.observation);
  ApiException? _error;

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _reload() async {
    final id = _entity?.id;
    if (id == null) return;
    try {
      final entity = Entity.from((await context.api.get('/entities/$id', query: {'filter[active]': 'all'})).resource);
      if (mounted) setState(() => _entity = entity);
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final entity = _entity;
    final body = resourceData('entities', id: entity?.id, attributes: {
      'abbreviation': _abbreviation.text.trim().toUpperCase(),
      'number': _optional(_number),
      'name': _name.text.trim(),
      'description': _optional(_description),
      'observation': _optional(_observation),
    });
    try {
      final api = context.api;
      final document = entity == null ? await api.post('/entities', body) : await api.patch('/entities/${entity.id}', body);
      if (!mounted) return;
      setState(() => _entity = Entity.from(document.resource));
      showMessage(context, entity == null ? 'Entidad creada. Ya puede ponerle una imagen.' : 'Entidad guardada.');
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  Future<void> _setActive(bool active) async {
    final e = _entity!;
    final ok = await runAction(context, () => context.api.patch('/entities/${e.id}', resourceData('entities', id: e.id, attributes: {'active': active})),
        success: active ? 'Entidad reactivada.' : 'Entidad desactivada.');
    if (ok) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final e = _entity;
    final manage = me.canAnywhere(Op.entitiesManage);
    return AppScaffold(
      title: e == null ? 'Entidad nueva' : e.abbreviation,
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.save, label: 'Guardar', enabled: manage, onPressed: _save),
        ActionItem(
          icon: Icons.tune,
          label: 'Ajustes de la Entidad',
          enabled: e != null && me.can(Op.settingsEntity, entityId: e.id),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalSettingsScreen.entity(entity: e))),
        ),
        const ActionItem.divider(),
        if (e == null || e.active)
          ActionItem(
            icon: Icons.toggle_off_outlined,
            label: 'Desactivar',
            enabled: e != null && manage,
            confirmation: 'Sus trabajadores no podrán unirse a ella mientras esté desactivada. ¿Desactivarla?',
            onPressed: () => _setActive(false),
          )
        else
          ActionItem(icon: Icons.toggle_on_outlined, label: 'Reactivar', enabled: manage, onPressed: () => _setActive(true)),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          ImageEditor(url: e?.imageUrl, icon: Icons.apartment, uploadPath: e != null && manage ? '/entities/${e.id}/image' : null, onChanged: _reload),
          if (e == null)
            const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: Text('La imagen se pone después de crearla.'))),
          if (e != null && !e.active) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CardChip('Desactivada', color: Colors.grey))),
          const SizedBox(height: 16),
          TextFormField(
            controller: _abbreviation,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(labelText: 'Abreviatura', hintText: 'p. ej. UMIM', errorText: _error?.fieldError('/abbreviation')),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(15)],
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Escriba de 2 a 15 letras y números.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _number,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(labelText: 'Número (opcional)', hintText: 'p. ej. 0123', errorText: _error?.fieldError('/number')),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            validator: (v) => (v ?? '').isEmpty || v!.length == 4 ? null : 'Escriba 4 dígitos.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            readOnly: !manage,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'p. ej. Unidad Militar de Ingeniería Mecánica'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escriba el nombre.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, readOnly: !manage, decoration: const InputDecoration(labelText: 'Descripción (opcional)'), maxLines: 3, minLines: 1),
          const SizedBox(height: 12),
          TextFormField(controller: _observation, readOnly: !manage, decoration: const InputDecoration(labelText: 'Observación (opcional)'), maxLines: 3, minLines: 1),
          if (_error != null && _error!.fieldError('/abbreviation') == null && _error!.fieldError('/number') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}
