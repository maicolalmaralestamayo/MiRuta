import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../guest/developer_chat_screen.dart';
import '../widgets/common.dart';
import 'entity_field.dart';
import 'password_fields.dart';

/// "Ya me registró un superior" (docs/08-version-2.md §8.3): con la Entidad,
/// el Pase y el código que le dio su superior, el trabajador elige su
/// usuario y su contraseña.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _form = GlobalKey<FormState>();
  final _abbreviation = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ApiException? _error;

  Future<void> _activate() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.activate(
        abbreviation: _abbreviation.text,
        pass: int.parse(_pass.text),
        code: _code.text,
        username: _username.text,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ya me registró un superior'), actions: const [DeveloperChatAction()]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Escribe los datos que te dio tu Jefe de Transporte o tu Jefe de itinerario, y elige tu usuario y tu contraseña.'),
          const SizedBox(height: 16),
          EntityAbbreviationField(controller: _abbreviation, guest: true),
          const SizedBox(height: 12),
          PassField(controller: _pass),
          const SizedBox(height: 12),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Código de activación', hintText: 'XXXX-XXXX', prefixIcon: Icon(Icons.key_outlined)),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => (v?.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length ?? 0) == 8 ? null : 'El código tiene 8 caracteres',
          ),
          const Divider(height: 32),
          TextFormField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Usuario que quieres',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: 'De ${Username.minLength} a ${Username.maxLength} caracteres; letras sin tilde, números, punto o guion bajo.',
              helperMaxLines: 2,
              errorText: _error?.fieldError('/username'),
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(Username.maxLength)],
            validator: validateUsername,
          ),
          const SizedBox(height: 12),
          PasswordFields(password: _password, confirmation: _confirmation, personal: () => [_username.text]),
          if (_error != null && _error!.fieldError('/username') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _activate, showErrors: false, child: const Text('Activar mi cuenta')),
        ]),
      ),
    );
  }
}
