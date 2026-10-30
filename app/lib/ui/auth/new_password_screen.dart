import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../widgets/common.dart';

/// Contraseña nueva obligatoria tras entrar con un código de restablecimiento.
/// No se puede usar la app hasta completarla.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.setNewPassword(_password.text);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Elige una contraseña nueva'), automaticallyImplyLeading: false),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Hola, ${context.me.firstName}. Entraste con un código: elige una contraseña nueva para seguir.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña nueva', helperText: 'Al menos 8 caracteres'),
              validator: (v) => v == null || v.length < 8 ? 'Al menos 8 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la contraseña'),
              validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar y entrar')),
            TextButton(onPressed: () => context.session.logout(), child: const Text('Cerrar sesión')),
          ]),
        ),
      ),
    );
  }
}
