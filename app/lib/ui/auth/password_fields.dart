import 'package:flutter/material.dart';

import '../../core/password_policy.dart';
import '../widgets/common.dart';

/// Contraseña nueva y su repetición, con los requisitos de la app
/// (docs/08-version-2.md §8.4). [personal]: usuario y nombres, que no puede contener.
class PasswordFields extends StatefulWidget {
  final TextEditingController password;
  final TextEditingController confirmation;
  final List<String> Function() personal;
  final String label;

  const PasswordFields({super.key, required this.password, required this.confirmation, required this.personal, this.label = 'Contraseña'});

  @override
  State<PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<PasswordFields> {
  PasswordPolicy _policy = const PasswordPolicy();
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    PasswordPolicy.load(() => context.api.get('/password-policy')).then((policy) {
      if (mounted) setState(() => _policy = policy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextFormField(
        controller: widget.password,
        obscureText: _hidden,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline),
          helperText: _policy.description,
          helperMaxLines: 3,
          suffixIcon: IconButton(icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hidden = !_hidden)),
        ),
        validator: (value) => _policy.validate(value, personal: widget.personal()),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: widget.confirmation,
        obscureText: _hidden,
        decoration: const InputDecoration(labelText: 'Repite la contraseña', prefixIcon: Icon(Icons.lock_outline)),
        validator: (value) => value != widget.password.text ? 'Las contraseñas no coinciden' : null,
      ),
    ]);
  }
}
