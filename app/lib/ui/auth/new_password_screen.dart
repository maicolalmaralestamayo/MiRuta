import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../widgets/common.dart';
import 'password_fields.dart';

/// Contraseña nueva obligatoria (docs/08-version-2.md §8.4): cuando caduca
/// (cada año) o tras recuperar el acceso. No se puede usar la app hasta
/// completarla. Si caducó, se pide también la actual.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;
  bool _hiddenCurrent = true;

  Future<void> _save(bool currentRequired) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.setNewPassword(_password.text, currentPassword: currentRequired ? _current.text : null);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final currentRequired = me.account.currentPasswordRequired;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Contraseña nueva'), automaticallyImplyLeading: false),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(currentRequired
                ? 'Su contraseña caducó: elija una nueva para seguir usando la app.'
                : 'Recuperó el acceso: elija una contraseña nueva para seguir.'),
            const SizedBox(height: 16),
            if (currentRequired) ...[
              TextFormField(
                controller: _current,
                obscureText: _hiddenCurrent,
                decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  prefixIcon: const Icon(Icons.lock_clock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_hiddenCurrent ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hiddenCurrent = !_hiddenCurrent),
                  ),
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => v == null || v.isEmpty ? 'Escriba su contraseña actual' : null,
              ),
              const SizedBox(height: 12),
            ],
            PasswordFields(password: _password, confirmation: _repeat, label: 'Contraseña nueva'),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            BusyButton(onPressed: () => _save(currentRequired), showErrors: false, icon: const Icon(Icons.login), child: const Text('Guardar contraseña y entrar')),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: () => context.session.logout(), icon: const Icon(Icons.logout), label: const Text('Cerrar sesión')),
            const SizedBox(height: 16),
            const DeveloperChatButton(),
          ]),
        ),
      ),
    );
  }
}
