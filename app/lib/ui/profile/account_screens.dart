import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../auth/password_fields.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Cambiar la contraseña (pide la actual). Las demás sesiones se cierran.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.setNewPassword(_password.text, currentPassword: _current.text);
      if (!mounted) return;
      showMessage(context, 'Contraseña cambiada. Se cerró la sesión en sus otros teléfonos.');
      Navigator.pop(context);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cambiar contraseña',
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña actual', prefixIcon: Icon(Icons.lock_clock_outlined)),
            validator: (v) => v == null || v.isEmpty ? 'Escriba su contraseña actual' : null,
          ),
          const SizedBox(height: 12),
          PasswordFields(
            password: _password,
            confirmation: _repeat,
            label: 'Contraseña nueva',
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, icon: const Icon(Icons.lock_reset), child: const Text('Cambiar contraseña')),
        ]),
      ),
    );
  }
}
