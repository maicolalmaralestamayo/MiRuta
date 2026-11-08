import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../management/forms.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';
import '../widgets/marks.dart';

/// Hijos (docs/11 §11.11 y §11.50, maqueta G18 n.º 13).
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final _view = GlobalKey<DataViewState<List<Child>>>();
  final _marks = Marks();

  Future<List<Child>> _load() async => (await context.api.getAll('/children', query: {'filter[parent]': context.me.userId})).map(Child.from).toList();

  Future<void> _open([Child? child]) async {
    await push(context, ChildForm(child: child));
    _view.currentState?.reload();
  }

  List<ActionItem> _actions() {
    final children = _view.currentState?.data ?? const <Child>[];
    if (!_marks.active) return [ActionItem(Icons.person_add_alt_1, 'Añadir hijo', () => _open())];
    final marked = _marks.of('child', children, (c) => c.id);
    return [
      ...markActions(_marks, children.map((c) => c.id)),
      if (marked.length == 1) ActionItem(Icons.edit_outlined, 'Editar', () => _open(marked.first)),
      ActionItem(Icons.delete_outline, 'Eliminar', () async {
        if (!await confirmDelete(context, marked.length == 1 ? 'a ${marked.first.fullName} de sus hijos' : '${marked.length} hijos de su lista',
            consequences: 'Solo se quitan de su lista: si otra persona los tiene declarados, los conserva.')) {
          return;
        }
        if (!mounted) return;
        for (final c in marked) {
          await context.api.delete('/children/${c.id}');
        }
        _marks.clear();
        _view.currentState?.reload();
      }, destructive: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Hijos',
      tab: MainTab.more,
      marks: _marks,
      actions: _actions,
      body: DataView<List<Child>>(
        key: _view,
        load: _load,
        builder: (context, children, reload) => ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
          FoldSection<Child>(
            storageKey: 'hijos',
            title: 'Hijos',
            items: children,
            emptyText: 'No ha declarado hijos. Use Acciones → Añadir hijo.',
            builder: (c) => ListenableBuilder(
              listenable: _marks,
              builder: (context, _) => InfoCard(
                images: [CardImage(url: c.photoUrl, icon: Icons.child_care, round: true, dim: !c.canTravel)],
                title: c.fullName,
                lines: ['Fecha nac.: ${formatDate(c.birthDate)}', c.eligible ? 'Derecho a viajar: ${formatDate(c.eligibleUntil)}' : 'Sin derecho a viajar'],
                chip: c.active ? null : const Chip2('Desactivado', grey),
                dim: !c.canTravel,
                selected: _marks.isMarked('child', c.id),
                onTap: () => _marks.active ? _marks.toggle('child', c.id) : _open(c),
                onLongPress: () => _marks.toggle('child', c.id),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Formulario del hijo (mismo estilo que el del trabajador).
class ChildForm extends StatefulWidget {
  final Child? child;

  const ChildForm({super.key, this.child});

  @override
  State<ChildForm> createState() => _ChildFormState();
}

class _ChildFormState extends State<ChildForm> {
  final _form = GlobalKey<FormState>();
  Child? get _c => widget.child;
  late final _first = TextEditingController(text: _c?.name.firstName);
  late final _middle = TextEditingController(text: _c?.name.middleName);
  late final _firstSurname = TextEditingController(text: _c?.name.firstSurname);
  late final _secondSurname = TextEditingController(text: _c?.name.secondSurname);
  late final _card = TextEditingController(text: _c?.identityCard);
  late bool _active = _c?.active ?? true;
  String? _photo;

  @override
  void initState() {
    super.initState();
    _photo = _c?.photoUrl;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final attributes = {
      ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
      'identityCard': _card.text.trim(),
    };
    final ok = await runAction(context, () async {
      if (_c == null) {
        final document = await context.api.post('/children', resourceData('children', attributes: attributes));
        final notice = document.meta['notice'];
        if (notice != null && mounted) showMessage(context, '$notice');
      } else {
        await context.api.patch('/children/${_c!.id}', resourceData('children', id: _c!.id, attributes: {...attributes, 'active': _active}));
      }
    }, success: _c == null ? null : 'Guardado.');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final api = context.api;
    if (!await confirmDelete(context, 'a ${_c!.fullName} de sus hijos')) return;
    if (!mounted) return;
    final ok = await runAction(context, () => api.delete('/children/${_c!.id}'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    final birth = _c?.birthDate ?? IdentityCard.birthDate(card);
    return AppScaffold(
      title: 'Hijo',
      tab: MainTab.more,
      actions: () => [
        ActionItem(Icons.save_outlined, 'Guardar', _save),
        if (_c != null)
          ActionItem(Icons.delete_outline, 'Eliminar', _delete, destructive: true),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          PhotoHeader(
            url: _photo,
            icon: Icons.child_care,
            onTap: _c == null
                ? null
                : () async {
                    final api = context.api;
                    if (await pickAndUpload(context, '/children/${_c!.id}/photo', 'photo')) {
                      final r = (await api.get('/children/${_c!.id}')).resource;
                      if (mounted) setState(() => _photo = r.string('photoUrl'));
                    }
                  },
          ),
          FormText(controller: _first, label: 'Primer nombre', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer nombre')),
          FormText(controller: _middle, label: 'Segundo nombre', capitalization: TextCapitalization.words),
          FormText(controller: _firstSurname, label: 'Primer apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer apellido')),
          FormText(controller: _secondSurname, label: 'Segundo apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el segundo apellido')),
          FormText(controller: _card, label: 'Carné de identidad', icon: Icons.badge_outlined, keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], validator: IdentityCard.validate),
          FormText(key: ValueKey('sex$card'), label: 'Sexo y nacimiento', value: sexAndBirth(_c?.sex ?? IdentityCard.sex(card), birth), readOnly: true),
          if (_c != null) FormText(label: 'Derecho a viajar hasta', value: formatDate(_c!.eligibleUntil), readOnly: true),
          if (_c != null && _c!.otherParents.isNotEmpty) FormText(label: 'También lo tiene declarado', value: _c!.otherParents.join(', '), readOnly: true),
          if (_c != null) ActiveSwitch(value: _active, onChanged: (v) => setState(() => _active = v)),
          if (_c == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('Si el niño ya lo declaró otra persona, con el carné se le asigna también a usted.')),
        ]),
      ),
    );
  }
}
