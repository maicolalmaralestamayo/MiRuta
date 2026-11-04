import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../../services/templates.dart';
import '../auth/names_fields.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'account_screens.dart';

/// Perfil (docs/11 §11.18; maqueta pantallas-final.png, 2): foto; nombres,
/// apellidos, carné y usuario editables; sexo y fecha de nacimiento de solo
/// lectura (salen del carné). Acciones: Guardar perfil y Cambiar contraseña.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final Person _person = context.me.person;
  late final _firstName = TextEditingController(text: _person.name.firstName);
  late final _middleName = TextEditingController(text: _person.name.middleName);
  late final _firstSurname = TextEditingController(text: _person.name.firstSurname);
  late final _secondSurname = TextEditingController(text: _person.name.secondSurname);
  late final _identityCard = TextEditingController(text: _person.identityCard ?? '');
  late final _username = TextEditingController(text: _person.username ?? '');
  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname);
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_firstName, _middleName, _firstSurname, _secondSurname, _identityCard, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    final card = _identityCard.text.trim();
    final username = Username.normalize(_username.text);
    try {
      await context.session.updateProfile(
        name: _names.value,
        identityCard: card == (_person.identityCard ?? '') ? null : card,
        username: username == _person.username ? null : username,
      );
      if (mounted) showMessage(context, 'Perfil guardado');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _photo() async {
    final me = context.me;
    final choice = await pickFrom<String>(context, 'Foto de perfil', ['camera', 'gallery', if (me.photoUrl != null) 'delete'],
        (c) => const {'camera': 'Hacer una foto', 'gallery': 'Elegir de la galería', 'delete': 'Quitar la foto'}[c]!);
    if (choice == null || !mounted) return;
    final session = context.session;
    if (choice == 'delete') {
      await runAction(context, () => session.api.delete('/me/photo'));
    } else {
      final file = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (file == null || !mounted) return;
      await runAction(context, () => session.api.upload('/me/photo', 'photo', file.path), success: 'Foto actualizada');
    }
    await session.reloadMe();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final card = _identityCard.text.trim();
    final birth = IdentityCard.birthDate(card) ?? (me.person.birthDate == null ? null : DateTime.tryParse(me.person.birthDate!));
    final sex = IdentityCard.sex(card) ?? me.person.sex;
    final expires = me.person.passwordExpiresAt;
    return AppScaffold(
      title: 'Perfil',
      actions: [
        ActionItem(icon: Icons.save, label: 'Guardar perfil', onPressed: _save),
        ActionItem(
          icon: Icons.password,
          label: 'Cambiar contraseña',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
        ),
      ],
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          Center(
            child: GestureDetector(
              onTap: _photo,
              child: Stack(children: [
                CardImage(url: me.photoUrl, icon: Icons.person, round: true, size: 104),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.secondary, child: const Icon(Icons.photo_camera, size: 18, color: Colors.black)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _names,
          TextFormField(
            controller: _identityCard,
            decoration: InputDecoration(
              labelText: 'Carné de identidad',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _error?.fieldError('/identityCard'),
              errorMaxLines: 4,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            validator: IdentityCard.validate,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Sexo y nacimiento', suffixIcon: Icon(Icons.lock_outline, size: 18)),
            child: Text([sexLabel(sex), if (birth != null) formatShortDate(birth)].where((s) => s.isNotEmpty).join(' • ')),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _username,
            decoration: InputDecoration(labelText: 'Usuario', prefixIcon: const Icon(Icons.alternate_email), errorText: _error?.fieldError('/username'), errorMaxLines: 3),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(Username.maxLength)],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateUsername,
          ),
          if (expires != null) ...[
            const SizedBox(height: 12),
            Text('Su contraseña caduca el ${formatDate(expires)}.', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_error != null && _error!.fieldError('/username') == null && _error!.fieldError('/identityCard') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}
