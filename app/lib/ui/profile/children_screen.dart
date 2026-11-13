import 'package:flutter/foundation.dart';
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

/// Formulario del hijo (mismo estilo que el del trabajador). Se abre desde
/// Inicio y desde el formulario del Trabajador (docs/11 §11.59 y §11.60).
class ChildForm extends StatefulWidget {
  final Child? child;

  /// Padre o madre a quien se le añade (el Administrador, a otra persona; null = uno mismo).
  final String? parentId;

  const ChildForm({super.key, this.child, this.parentId});

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
  late final List<Object?> _initial = _snapshot();
  bool _leaving = false;

  List<Object?> _snapshot() => [_first.text, _middle.text, _firstSurname.text, _secondSurname.text, _card.text, _active];

  bool get _dirty => !_leaving && !listEquals(_initial, _snapshot());

  @override
  void initState() {
    super.initState();
    _photo = _c?.photoUrl;
    _initial;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final attributes = {
      ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
      'identityCard': _card.text.trim(),
    };
    final me = context.me;
    final ok = await runAction(context, () async {
      if (_c == null) {
        await context.api.post(
          '/children',
          resourceData('children', attributes: attributes, relationships: {if (widget.parentId != null && widget.parentId != me.userId) 'parent': ResourceId('users', widget.parentId!)}),
        );
      } else {
        await context.api.patch('/children/${_c!.id}', resourceData('children', id: _c!.id, attributes: {...attributes, 'active': _active}));
      }
    }, success: _c == null ? 'Hijo añadido' : 'Hijo actualizado');
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final api = context.api;
    if (!await confirmDelete(context, 'a ${_c!.fullName} de la lista de hijos', consequences: 'Si otra persona lo tiene declarado, lo conserva.')) return;
    if (!mounted) return;
    final ok = await runAction(context, () => api.delete('/children/${_c!.id}'), success: 'Hijo quitado');
    if (ok && mounted) {
      _leaving = true;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    final birth = _c?.birthDate ?? IdentityCard.birthDate(card);
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold(
        title: 'Hijo',
        tab: MainTab.home,
        actions: () => [ActionItem(Icons.save_outlined, 'Guardar', _save), if (_c != null) ActionItem(Icons.delete_outline, 'Eliminar', _delete, destructive: true)],
        body: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
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
              FormText(
                controller: _card,
                label: 'Carné de identidad',
                icon: Icons.badge_outlined,
                keyboard: TextInputType.number,
                last: true,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                validator: IdentityCard.validate,
              ),
              FormText(key: ValueKey('sex$card'), label: 'Sexo y nacimiento', value: sexAndBirth(_c?.sex ?? IdentityCard.sex(card), birth), readOnly: true),
              if (_c != null) FormText(label: 'Derecho a viajar hasta', value: formatDate(_c!.eligibleUntil), readOnly: true),
              if (_c != null && _c!.otherParents.isNotEmpty) FormText(label: 'También lo tiene declarado', value: _c!.otherParents.join(', '), readOnly: true),
              if (_c != null) ActiveSwitch(value: _active, onChanged: (v) => setState(() => _active = v)),
              if (_c == null) const Padding(padding: EdgeInsets.all(16), child: Text('Si el niño ya lo declaró otra persona, con el carné se le asigna también a usted.')),
            ],
          ),
        ),
      ),
    );
  }
}
