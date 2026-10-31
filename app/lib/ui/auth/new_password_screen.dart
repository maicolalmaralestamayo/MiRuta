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
        appBar: AppBar(title: const Text('Elige una contraseña nueva'), automaticallyImplyLeading: false),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(currentRequired
                ? 'Hola, ${me.firstName}. Tu contraseña caducó: elige una nueva para seguir usando la app.'
                : 'Hola, ${me.firstName}. Recuperaste el acceso: elige una contraseña nueva para seguir.'),
            const SizedBox(height: 16),
            if (currentRequired) ...[
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña actual', prefixIcon: Icon(Icons.lock_clock_outlined)),
                validator: (v) => v == null || v.isEmpty ? 'Escribe tu contraseña actual' : null,
              ),
              const SizedBox(height: 12),
            ],
            PasswordFields(
              password: _password,
              confirmation: _repeat,
              label: 'Contraseña nueva',
              personal: () => [me.username ?? '', me.name.firstName, me.name.middleName, me.name.firstSurname, me.name.secondSurname],
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            BusyButton(onPressed: () => _save(currentRequired), showErrors: false, child: const Text('Guardar y entrar')),
            TextButton(onPressed: () => context.session.logout(), child: const Text('Cerrar sesión')),
          ]),
        ),
      ),
    );
  }
}
