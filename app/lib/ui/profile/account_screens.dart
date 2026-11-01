import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../services/session.dart';
import '../auth/names_fields.dart';
import '../auth/password_fields.dart';
import '../widgets/common.dart';

/// Cambiar los cuatro nombres de la cuenta.
class EditNamesScreen extends StatefulWidget {
  const EditNamesScreen({super.key});

  @override
  State<EditNamesScreen> createState() => _EditNamesScreenState();
}

class _EditNamesScreenState extends State<EditNamesScreen> {
  final _form = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: context.me.name.firstName);
  late final _middleName = TextEditingController(text: context.me.name.middleName);
  late final _firstSurname = TextEditingController(text: context.me.name.firstSurname);
  late final _secondSurname = TextEditingController(text: context.me.name.secondSurname);
  late final _names = NamesFields(firstName: _firstName, middleName: _middleName, firstSurname: _firstSurname, secondSurname: _secondSurname);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await context.api.patch('/me', resourceData('users', attributes: Session.nameAttributes(_names.value)));
    if (!mounted) return;
    await context.session.reloadMe();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nombres y apellidos')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _names,
          const SizedBox(height: 8),
          BusyButton(onPressed: _save, icon: const Icon(Icons.save), child: const Text('Guardar nombres y apellidos')),
        ]),
      ),
    );
  }
}

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
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
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
