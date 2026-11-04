import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/roles_api.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';

/// Íconos que se pueden elegir para un rol (nombres de íconos Material; ver `roleIcon`).
const roleIconChoices = [
  'badge', 'directions_bus', 'groups', 'manage_accounts', 'engineering', 'support_agent', 'local_shipping', 'verified_user', 'person',
];

/// Una línea con las marcas de un rol: «Por defecto • Se puede solicitar • De itinerario».
String roleFlags(Role role) => [
      if (role.isAdministrator) 'Todas las operaciones',
      if (role.isDefault) 'Por defecto',
      if (role.requestable) 'Se puede solicitar',
      if (role.itineraryScoped) 'De itinerario',
    ].join(' • ');

/// Roles (Gestión, docs/11 §11.16): el Administrador (fijo, de solo lectura)
/// y los roles configurables. Crear, editar y eliminar (aunque esté
/// asignado: lo pierden quienes lo tengan) y consultar la tabla de operaciones.
class RolesAdminScreen extends StatefulWidget {
  const RolesAdminScreen({super.key});

  @override
  State<RolesAdminScreen> createState() => _RolesAdminScreenState();
}

class _RolesAdminScreenState extends State<RolesAdminScreen> {
  final _view = GlobalKey<AsyncViewState<List<Role>>>();
  final _selection = SelectionController();
  List<Role> _roles = const [];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<List<Role>> _load() async {
    final roles = await RolesApi(context.api).all();
    _roles = roles;
    _selection.retain(roles.map((r) => r.id));
    return roles;
  }

  Future<void> _open(Role? role) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RoleFormScreen(role: role, roles: _roles)));
    if (saved == true) _view.currentState?.reload();
  }

  Future<void> _delete() async {
    final selected = _selection.selectedOf(_roles, (r) => r.id);
    final api = context.api;
    final ok = await runAction(context, () async {
      for (final r in selected) {
        await api.delete('/roles/${r.id}');
      }
    }, success: selected.length == 1 ? 'Rol eliminado.' : 'Roles eliminados.');
    if (ok) {
      _selection.clear();
      _view.currentState?.reload();
    }
  }

  String _deleteMessage() {
    final selected = _selection.selectedOf(_roles, (r) => r.id);
    final holders = selected.fold<int>(0, (sum, r) => sum + (r.holderCount ?? 0));
    final names = selected.map((r) => r.name).join(', ');
    return holders == 0
        ? '¿Eliminar $names?'
        : '¿Eliminar $names? ${plural(holders, 'persona lo tiene', 'personas lo tienen')} asignado: lo perderán ahora y recibirán el aviso de rol quitado.';
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final manage = me.canAnywhere(Op.rolesManage);
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => AppScaffold(
        title: 'Roles',
        tab: MainTab.more,
        selection: _selection,
        actions: [
          ActionItem(icon: Icons.add_moderator_outlined, label: 'Crear rol', enabled: manage, onPressed: () => _open(null)),
          ActionItem(
            icon: Icons.table_chart_outlined,
            label: 'Tabla de operaciones',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperationsScreen())),
          ),
          const ActionItem.divider(),
          ActionItem(icon: Icons.edit_outlined, label: 'Editar', needs: ActionNeeds.one, onPressed: () => _open(_selection.selectedOf(_roles, (r) => r.id).first)),
          ActionItem(
            icon: Icons.delete_outline,
            label: 'Eliminar',
            needs: ActionNeeds.some,
            destructive: true,
            enabled: manage,
            confirmation: _selection.active ? _deleteMessage() : null,
            onPressed: _delete,
          ),
        ],
        body: AsyncView<List<Role>>(
          key: _view,
          load: _load,
          builder: (context, roles, reload) => SelectableCardList<Role>(
            controller: _selection,
            sections: [
              CardSection(title: 'Fijo', items: roles.where((r) => r.isAdministrator).toList()),
              CardSection(title: 'Configurables', items: roles.where((r) => !r.isAdministrator).toList(), hideIfEmpty: false, emptyText: 'No hay roles.'),
            ],
            keyOf: (r) => r.id,
            canSelect: (r) => r.editable && !r.isAdministrator,
            onOpen: _open,
            cardBuilder: (context, r, selected, onTap, onLongPress) => RoleCard(
              name: r.name,
              icon: r.icon,
              subtitle: roleFlags(r).isEmpty ? 'Lo asigna quien tenga permiso' : roleFlags(r),
              extraLine: r.isAdministrator ? 'No se puede editar ni eliminar' : (r.holderCount == null ? null : plural(r.holderCount!, 'persona', 'personas')),
              selected: selected,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
          ),
        ),
      ),
    );
  }
}

/// Crear o editar un rol: nombre, ícono, si se puede solicitar, si es el
/// rol por defecto, si es de itinerario, sus operaciones con su ámbito (de la
/// tabla fija) y qué roles aprueban sus solicitudes. El Administrador se
/// muestra de solo lectura.
class RoleFormScreen extends StatefulWidget {
  final Role? role;

  /// Todos los roles (para elegir los aprobadores).
  final List<Role> roles;

  const RoleFormScreen({super.key, this.role, this.roles = const []});

  @override
  State<RoleFormScreen> createState() => _RoleFormScreenState();
}

class _RoleFormScreenState extends State<RoleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.role?.name);
  late String? _icon = widget.role?.icon;
  late bool _requestable = widget.role?.requestable ?? false;
  late bool _isDefault = widget.role?.isDefault ?? false;
  late bool _itineraryScoped = widget.role?.itineraryScoped ?? false;

  /// operación → ámbito elegido.
  late final Map<String, String> _scopes = {for (final p in widget.role?.permissions ?? const <({String operation, String scope})>[]) p.operation: p.scope};
  late final Set<String> _approvers = {...?widget.role?.approverRoleIds};
  List<Operation>? _operations;
  String? _error;

  bool get _readOnly {
    final role = widget.role;
    if (role != null && (!role.editable || role.isAdministrator)) return true;
    final me = context.me;
    return !me.canAnywhere(Op.rolesManage) && !me.canAnywhere(Op.rolesSetDefault);
  }

  /// Solo puede elegir el rol por defecto (roles.set_default sin roles.manage).
  bool get _onlyDefault => !context.me.canAnywhere(Op.rolesManage) && context.me.canAnywhere(Op.rolesSetDefault);

  @override
  void initState() {
    super.initState();
    RolesApi(context.api).operations().then((ops) {
      if (mounted) setState(() => _operations = ops);
    }).catchError((Object error) {
      if (mounted) setState(() => _error = 'No se pudo cargar la tabla de operaciones.');
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final role = widget.role;
    final attributes = _onlyDefault
        ? {'isDefault': _isDefault}
        : {
            'name': _name.text.trim(),
            'icon': _icon,
            'requestable': _requestable,
            if (context.me.canAnywhere(Op.rolesSetDefault)) 'isDefault': _isDefault,
            'itineraryScoped': _itineraryScoped,
            'permissions': [for (final e in _scopes.entries) {'operation': e.key, 'scope': e.value}],
            'approverRoleIds': [..._approvers],
          };
    final body = resourceData('roles', id: role?.id, attributes: attributes);
    final api = context.api;
    final ok = await runAction(context, () => role == null ? api.post('/roles', body) : api.patch('/roles/${role.id}', body), success: 'Rol guardado.');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final role = widget.role!;
    final api = context.api;
    if (await runAction(context, () => api.delete('/roles/${role.id}'), success: 'Rol eliminado.') && mounted) Navigator.pop(context, true);
  }

  Widget _operationRow(Operation op, bool readOnly) {
    final current = _scopes[op.key];
    return ListTile(
      dense: true,
      title: Text(op.name),
      subtitle: Text(op.key, style: Theme.of(context).textTheme.bodySmall),
      trailing: SizedBox(
        width: 140,
        child: DropdownButton<String?>(
          isExpanded: true,
          value: current,
          hint: const Text('—'),
          onChanged: readOnly ? null : (v) => setState(() => v == null ? _scopes.remove(op.key) : _scopes[op.key] = v),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No')),
            for (final s in op.scopes) DropdownMenuItem<String?>(value: s, child: Text(Scope.label(s))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final readOnly = _readOnly;
    final structural = readOnly || _onlyDefault;
    final groups = <String, List<Operation>>{};
    for (final op in _operations ?? const <Operation>[]) {
      groups.putIfAbsent(op.group, () => []).add(op);
    }
    final others = widget.roles.where((r) => !r.isAdministrator && r.id != role?.id).toList();
    return AppScaffold(
      title: role == null ? 'Rol nuevo' : role.name,
      tab: MainTab.more,
      actions: [
        ActionItem(icon: Icons.save, label: 'Guardar', enabled: !readOnly, onPressed: _save),
        ActionItem(
          icon: Icons.delete_outline,
          label: 'Eliminar',
          destructive: true,
          enabled: role != null && !readOnly && context.me.canAnywhere(Op.rolesManage),
          confirmation: (role?.holderCount ?? 0) > 0
              ? '¿Eliminar ${role!.name}? ${plural(role.holderCount!, 'persona lo tiene', 'personas lo tienen')} asignado: lo perderán ahora y recibirán el aviso de rol quitado.'
              : '¿Eliminar ${role?.name ?? 'el rol'}?',
          onPressed: _delete,
        ),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 96), children: [
          if (role?.isAdministrator == true)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('El Administrador tiene todas las operaciones con ámbito «Todas». No se puede editar ni eliminar, y siempre hay al menos uno.'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              controller: _name,
              readOnly: structural,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'p. ej. Chofer'),
              textCapitalization: TextCapitalization.sentences,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Escriba el nombre del rol.' : null,
            ),
          ),
          const SectionHeader('Ícono'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final name in roleIconChoices)
                ChoiceChip(
                  label: Icon(roleIcon(name), size: 22),
                  selected: _icon == name,
                  onSelected: structural ? null : (s) => setState(() => _icon = s ? name : null),
                ),
            ]),
          ),
          SwitchListTile(
            title: const Text('Se puede solicitar'),
            subtitle: const Text('Si no, solo lo asigna quien tenga permiso.'),
            value: _requestable,
            onChanged: structural ? null : (v) => setState(() => _requestable = v),
          ),
          SwitchListTile(
            title: const Text('Rol por defecto'),
            subtitle: const Text('Se asigna al aprobarse la entrada en una Entidad.'),
            value: _isDefault,
            onChanged: readOnly || !context.me.canAnywhere(Op.rolesSetDefault) ? null : (v) => setState(() => _isDefault = v),
          ),
          SwitchListTile(
            title: const Text('De itinerario'),
            subtitle: const Text('Se asigna con un itinerario (un solo itinerario por Entidad).'),
            value: _itineraryScoped,
            onChanged: structural ? null : (v) => setState(() => _itineraryScoped = v),
          ),
          if (role?.isAdministrator != true) ...[
            const SectionHeader('Aprueban sus solicitudes'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Además del Administrador, que siempre puede.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in others)
                  FilterChip(
                    label: Text(r.name),
                    selected: _approvers.contains(r.id),
                    onSelected: structural ? null : (s) => setState(() => s ? _approvers.add(r.id) : _approvers.remove(r.id)),
                  ),
              ]),
            ),
          ],
          const SectionHeader('Operaciones y ámbito'),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_operations == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(group.key, style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final op in group.value) _operationRow(op, structural),
          ],
        ]),
      ),
    );
  }
}

/// Tabla fija de operaciones (docs/11 §11.16): solo se consulta.
class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Tabla de operaciones',
      tab: MainTab.more,
      body: AsyncView<List<Operation>>(
        load: () => RolesApi(context.api).operations(),
        builder: (context, operations, reload) {
          final groups = <String, List<Operation>>{};
          for (final op in operations) {
            groups.putIfAbsent(op.group, () => []).add(op);
          }
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('La tabla viene con la app y no se puede editar. Lo propio (perfil, hijos, ausencias, solicitudes, ajustes y QR) lo puede siempre cada persona.'),
            ),
            for (final group in groups.entries) ...[
              SectionHeader(group.key),
              for (final op in group.value)
                ListTile(
                  dense: true,
                  title: Text(op.name),
                  subtitle: Text('${op.scopes.map(Scope.label).join(', ')} · ${op.key}'),
                ),
            ],
          ]);
        },
      ),
    );
  }
}
