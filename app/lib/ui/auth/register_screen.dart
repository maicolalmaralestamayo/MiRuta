import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../guest/developer_chat_screen.dart';
import '../widgets/common.dart';
import 'names_fields.dart';
import 'password_fields.dart';

/// Paso 1 del registro: crear la cuenta (docs/08-version-2.md §8.3). Después
/// la app pide unirse a la Entidad.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _firstSurname = TextEditingController();
  final _secondSurname = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ApiException? _error;

  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname);

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.register(name: _names.value, username: _username.text, password: _password.text);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta'), actions: const [DeveloperChatAction()]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _names,
          TextFormField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Usuario',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: 'Lo eliges tú: con él entrarás. De ${Username.minLength} a ${Username.maxLength} caracteres; letras sin tilde, números, punto o guion bajo.',
              helperMaxLines: 3,
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
          PasswordFields(
            password: _password,
            confirmation: _confirmation,
            personal: () => [_username.text, _firstName.text, _middleName.text, _firstSurname.text, _secondSurname.text],
          ),
          if (_error != null && _error!.fieldError('/username') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _register, showErrors: false, child: const Text('Crear cuenta')),
        ]),
      ),
    );
  }
}
