import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/api/roles_api.dart';
import '../../services/templates.dart';
import '../auth/names_fields.dart';
import '../navigation.dart';
import '../qr/printed_qr.dart';
import '../settings/scoped_settings_screen.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';
import 'management.dart';
import 'worker_actions.dart';

/// Ficha de un trabajador en una Entidad (Gestión): sus datos (editables con
/// workers.edit; el carné solo si se puede ver), su itinerario y parada y sus
/// roles. Acciones: guardar, asignar o quitar itinerario y parada, asignar o
/// quitar roles, sus ajustes, el QR impreso, desactivar y dar de baja.
class WorkerFormScreen extends StatefulWidget {
  final WorkerItem item;
  final Entity entity;

  const WorkerFormScreen({super.key, required this.item, required this.entity});

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _roleSelection = SelectionController();
  late WorkerItem _item = widget.item;
  late final _firstName = TextEditingController(text: _worker.name.firstName);
  late final _middleName = TextEditingController(text: _worker.name.middleName);
  late final _firstSurname = TextEditingController(text: _worker.name.firstSurname);
  late final _secondSurname = TextEditingController(text: _worker.name.secondSurname);
  late final _identityCard = TextEditingController(text: _worker.identityCard ?? '');
  late bool _hasPhone = _worker.hasPhone;

  /// Rol por defecto (se muestra como «Trabajador», siempre primero).
  String? _defaultRoleId;
  Map<String, String> _itineraryNames = {};

  Worker get _worker => _item.worker;

  Entity get _entity => widget.entity;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  @override
  void dispose() {
    _roleSelection.dispose();
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _identityCard]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final api = context.api;
    try {
      final roles = await RolesApi(api).all();
      final itineraries = await MembershipsApi(api).itineraries(_entity.id);
      if (!mounted) return;
      setState(() {
        _defaultRoleId = roles.where((r) => r.isDefault).firstOrNull?.id;
        _itineraryNames = {for (final i in itineraries) i.id: i.name};
      });
    } catch (_) {
      // Sin los nombres, las tarjetas muestran la Entidad.
    }
  }

  Future<void> _reload() async {
    try {
      final document = await context.api.get('/workers/${_worker.id}', query: {'filter[active]': 'all', 'include': WorkerItem.include});
      if (!mounted) return;
      setState(() {
        _item = WorkerItem.from(document.resource);
        _hasPhone = _worker.hasPhone;
      });
      _roleSelection.retain(_worker.roles.map((r) => r.id));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  bool get _canEdit => context.me.can(Op.workersEdit, entityId: _entity.id, itineraryId: _worker.itineraryId);

  PersonName get _name => PersonName(
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        firstSurname: _firstSurname.text.trim(),
        secondSurname: _secondSurname.text.trim(),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final card = _identityCard.text.trim();
    final attributes = {
      ..._name.toAttributes(),
      'hasPhone': _hasPhone,
      if (_worker.identityCard != null && card != _worker.identityCard) 'identityCard': card,
    };
    final ok = await runAction(context, () => context.api.patch('/workers/${_worker.id}', resourceData('workers', id: _worker.id, attributes: attributes)),
        success: 'Datos guardados.');
    if (ok) await _reload();
  }

  Future<void> _then(Future<bool> action) async {
    if (await action) {
      _roleSelection.clear();
      await _reload();
    }
  }

  List<HeldRole> get _extraRoles => _worker.roles.where((r) => r.roleId != _defaultRoleId).toList();

  List<ActionItem> _actions() {
    final me = context.me;
    final e = _entity;
    final w = _worker;
    final selectedRoles = _roleSelection.selectedOf(_extraRoles, (r) => r.id);
    final settingsAllowed = me.can(Op.settingsWorker, entityId: e.id, itineraryId: w.itineraryId) && w.userId != null;
    return [
      ActionItem(icon: Icons.save, label: 'Guardar', enabled: _canEdit && w.active, onPressed: _save),
      ActionItem(
        icon: Icons.alt_route,
        label: w.itineraryId == null ? 'Asignar itinerario y parada' : 'Cambiar itinerario y parada',
        enabled: me.canInEntity(Op.membersAssign, e.id) && w.active,
        onPressed: () => _then(assignItineraryAndStop(context, [w], e)),
      ),
      ActionItem(
        icon: Icons.wrong_location_outlined,
        label: 'Quitar itinerario y parada',
        enabled: w.itineraryId != null && me.can(Op.membersAssign, entityId: e.id, itineraryId: w.itineraryId) && w.active,
        onPressed: () => _then(removeItineraryAndStop(context, [w])),
      ),
      ActionItem(
        icon: Icons.add_moderator_outlined,
        label: 'Asignar rol',
        enabled: me.can(Op.rolesAssign, entityId: e.id) && w.active,
        onPressed: () => _then(assignRole(context, [w], e)),
      ),
      ActionItem(
        icon: Icons.remove_moderator_outlined,
        label: 'Quitar rol',
        needs: ActionNeeds.some,
        enabled: me.can(Op.rolesAssign, entityId: e.id),
        onPressed: () => _then(removeRoles(context, w, selectedRoles)),
      ),
      const ActionItem.divider(),
      ActionItem(
        icon: Icons.tune,
        label: 'Ajustes del trabajador',
        enabled: settingsAllowed,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScopedSettingsScreen.worker(userId: w.userId!, name: w.fullName))),
      ),
      ActionItem(
        icon: Icons.qr_code_2,
        label: 'QR impreso',
        enabled: !w.hasPhone && me.can(Op.workersPrintedQr, entityId: e.id, itineraryId: w.itineraryId),
        onPressed: () => openPrintedQr(context, w),
      ),
      const ActionItem.divider(),
      if (w.active)
        ActionItem(
          icon: Icons.toggle_off_outlined,
          label: 'Desactivar',
          enabled: me.can(Op.workersDeactivate, entityId: e.id),
          confirmation: '¿Desactivar a ${w.fullName} en ${e.abbreviation}? Conserva su itinerario, su parada y sus roles.',
          onPressed: () => _then(setWorkersActive(context, [w], false)),
        )
      else
        ActionItem(
          icon: Icons.toggle_on_outlined,
          label: 'Reactivar',
          enabled: me.can(Op.workersDeactivate, entityId: e.id),
          onPressed: () => _then(setWorkersActive(context, [w], true)),
        ),
      ActionItem(
        icon: Icons.logout,
        label: 'Dar de baja de la Entidad',
        destructive: true,
        enabled: w.active && me.can(Op.entitiesAssignMembers, entityId: e.id),
        confirmation: 'Perderá su itinerario, su parada y sus roles en ${e.abbreviation}. Para volver tendrá que solicitarlo de nuevo. ¿Darlo de baja?',
        onPressed: () async {
          if (await removeFromEntity(context, [w]) && mounted) Navigator.pop(context);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final w = _worker;
    final canEdit = _canEdit && w.active;
    final card = _identityCard.text.trim();
    final birth = IdentityCard.birthDate(card);
    return ListenableBuilder(
      listenable: _roleSelection,
      builder: (context, _) => AppScaffold(
        title: 'Trabajador',
        tab: MainTab.more,
        selection: _roleSelection,
        selectionTitle: (n) => n == 1 ? '1 rol seleccionado' : '$n roles seleccionados',
        actions: _actions(),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 96), children: [
            Center(child: CardImage(url: w.photoUrl, icon: Icons.person, round: true, size: 96, dim: !w.active)),
            if (!w.active)
              const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CardChip('Desactivado', color: Colors.grey))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                AbsorbPointer(
                  absorbing: !canEdit,
                  child: NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname),
                ),
                if (w.identityCard != null) ...[
                  TextFormField(
                    controller: _identityCard,
                    readOnly: !canEdit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
                    decoration: const InputDecoration(labelText: 'Carné de identidad', prefixIcon: Icon(Icons.badge_outlined)),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: IdentityCard.validate,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  ReadOnlyField(
                    label: 'Sexo y nacimiento',
                    value: birth == null ? '' : '${sexLabel(IdentityCard.sex(card))} • ${formatShortDate(birth)}',
                  ),
                ] else
                  ReadOnlyField(label: 'Sexo', value: sexLabel(w.sex)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tiene teléfono'),
                  subtitle: Text(_hasPhone ? 'Usa el QR de la app.' : 'Usa un QR impreso.'),
                  value: _hasPhone,
                  onChanged: canEdit ? (v) => setState(() => _hasPhone = v) : null,
                ),
              ]),
            ),
            const SectionHeader('Itinerario y parada'),
            ItineraryStopCard(
              itineraryName: _item.itineraryName,
              itineraryImageUrl: _item.itineraryImageUrl,
              street: _item.stopStreet,
              landmark: _item.stopLandmark,
              stopImageUrl: _item.stopImageUrl,
              onTap: context.me.canInEntity(Op.membersAssign, _entity.id) && w.active ? () => _then(assignItineraryAndStop(context, [w], _entity)) : null,
            ),
            const SectionHeader('Roles'),
            if (w.active) RoleCard.worker(_entity),
            SelectableCardList<HeldRole>(
              controller: _roleSelection,
              scrollable: false,
              sections: [CardSection(items: _extraRoles)],
              keyOf: (r) => r.id,
              cardBuilder: (context, r, selected, onTap, onLongPress) => RoleCard(
                name: r.name,
                icon: r.icon,
                subtitle: r.itineraryId == null ? _entity.abbreviation : (_itineraryNames[r.itineraryId] ?? r.itineraryName ?? _entity.abbreviation),
                selected: selected,
                onTap: onTap,
                onLongPress: onLongPress,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
