import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../widgets/common.dart';
import 'names_fields.dart';
import 'password_fields.dart';

/// Paso 1 del registro, «Registrarme por primera vez» (docs/09 §3). Después
/// la app pide los otros datos del registro (Entidad, Pase…).
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
      appBar: AppBar(title: const Text('Registrarme por primera vez')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _names,
          TextFormField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Nombre de usuario',
              hintText: 'p. ej. ana.perez',
              prefixIcon: const Icon(Icons.person_outline),
              errorText: _error?.fieldError('/username'),
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(Username.maxLength)],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) {
              if (_error?.fieldError('/username') != null) setState(() => _error = null);
            },
            validator: validateUsername,
          ),
          const SizedBox(height: 12),
          PasswordFields(password: _password, confirmation: _confirmation),
          if (_error != null && _error!.fieldError('/username') == null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _register, showErrors: false, icon: const Icon(Icons.how_to_reg), child: const Text('Registrarme')),
          const SizedBox(height: 24),
          const DeveloperChatButton(),
        ]),
      ),
    );
  }
}
