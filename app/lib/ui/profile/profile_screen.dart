import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../auth/password_fields.dart';
import '../management/forms.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Perfil (docs/11 §11.50, maqueta G18 n.º 12): mismo estilo que el
/// formulario del trabajador.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late Me _me = context.read<Session>().me!;
  late final _first = TextEditingController(text: _me.name.firstName);
  late final _middle = TextEditingController(text: _me.name.middleName);
  late final _firstSurname = TextEditingController(text: _me.name.firstSurname);
  late final _secondSurname = TextEditingController(text: _me.name.secondSurname);
  late final _card = TextEditingController(text: _me.identityCard);
  late final _username = TextEditingController(text: _me.username);
  late List<Object?> _initial = _snapshot();

  List<Object?> _snapshot() => [_first.text, _middle.text, _firstSurname.text, _secondSurname.text, _card.text, _username.text];

  bool get _dirty => !listEquals(_initial, _snapshot());

  @override
  void initState() {
    super.initState();
    _initial;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runAction(context, () async {
      await context.api.patch('/me', resourceData('users', attributes: {
        ...PersonName(firstName: _first.text, middleName: _middle.text, firstSurname: _firstSurname.text, secondSurname: _secondSurname.text).toAttributes(),
        'identityCard': _card.text.trim(),
        'username': Username.normalize(_username.text),
      }));
      if (mounted) await context.read<Session>().reloadMe();
    }, success: 'Perfil actualizado');
    if (ok && mounted) setState(() => _initial = _snapshot());
  }

  Future<void> _photo() async {
    if (await pickAndUpload(context, '/me/photo', 'photo') && mounted) {
      await context.read<Session>().reloadMe();
      if (mounted) setState(() => _me = context.read<Session>().me!);
    }
  }

  Future<void> _removePhoto() async {
    await runAction(context, () async {
      await context.api.delete('/me/photo');
      if (mounted) await context.read<Session>().reloadMe();
    }, success: 'Foto quitada');
    if (mounted) setState(() => _me = context.read<Session>().me!);
  }

  Future<void> _changePassword() => showDialog<void>(context: context, builder: (_) => const _PasswordDialog());

  @override
  Widget build(BuildContext context) {
    final card = _card.text.trim();
    return LeaveGuard(
      dirty: () => _dirty,
      child: AppScaffold(
      title: 'Perfil',
      tab: MainTab.home,
      actions: () => [
        ActionItem(Icons.save_outlined, 'Guardar perfil', _save),
        ActionItem(Icons.password, 'Cambiar contraseña', _changePassword),
        ActionItem(Icons.photo_camera_outlined, 'Cambiar foto', _photo),
        if (_me.photoUrl != null) ActionItem(Icons.hide_image_outlined, 'Quitar foto', _removePhoto, destructive: true),
      ],
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
          PhotoHeader(url: _me.photoUrl, icon: Icons.person, onTap: _photo),
          FormText(controller: _first, label: 'Primer nombre', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer nombre')),
          FormText(controller: _middle, label: 'Segundo nombre', capitalization: TextCapitalization.words),
          FormText(controller: _firstSurname, label: 'Primer apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el primer apellido')),
          FormText(controller: _secondSurname, label: 'Segundo apellido', capitalization: TextCapitalization.words, validator: (v) => requiredText(v, 'Escriba el segundo apellido')),
          FormText(controller: _card, label: 'Carné de identidad', icon: Icons.badge_outlined, keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], validator: IdentityCard.validate),
          FormText(label: 'Sexo y nacimiento', value: sexAndBirth(_me.sex ?? IdentityCard.sex(card), _me.birthDate ?? IdentityCard.birthDate(card)), readOnly: true),
          FormText(controller: _username, label: 'Usuario', icon: Icons.alternate_email, validator: validateUsername, capitalization: TextCapitalization.none, last: true),
          FormText(label: 'Contraseña', value: _me.passwordExpiresAt == null ? 'Sin caducidad' : 'Caduca el ${formatDate(_me.passwordExpiresAt)}', readOnly: true),
        ]),
      ),
    ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.password, size: 32),
      title: const Text('Cambiar contraseña', textAlign: TextAlign.center),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Contraseña actual', prefixIcon: Icon(Icons.lock_clock_outlined)),
              validator: (v) => (v ?? '').isEmpty ? 'Escriba su contraseña actual' : null,
            ),
            const SizedBox(height: 12),
            PasswordFields(password: _password, confirmation: _repeat, label: 'Contraseña nueva'),
            const SizedBox(height: 8),
            const Text('Al cambiarla se cierran sus otras sesiones.'),
          ]),
        ),
      ),
      actions: [
        cancelButton(context),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  setState(() => _busy = true);
                  final body = resourceData('users', attributes: {'password': _password.text});
                  body['meta'] = {'currentPassword': _current.text};
                  final ok = await runAction(context, () => context.api.patch('/me', body), success: 'Contraseña cambiada');
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}
