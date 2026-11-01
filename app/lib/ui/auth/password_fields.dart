import 'package:flutter/material.dart';

import '../../core/password_policy.dart';
import '../widgets/common.dart';

/// Contraseña nueva y su repetición, con los requisitos de la app
/// (docs/08-version-2.md §8.4). Los dos campos llevan el ojo para verla y
/// no hay ayudas fijas: solo el error si incumple una regla (docs/09).
class PasswordFields extends StatefulWidget {
  final TextEditingController password;
  final TextEditingController confirmation;
  final String label;

  /// Sin uso: ya no se comprueba que la contraseña contenga el usuario o los
  /// nombres (docs/09 §32). Se conserva para no romper a quien lo pasa.
  final List<String> Function()? personal;

  const PasswordFields({super.key, required this.password, required this.confirmation, this.personal, this.label = 'Contraseña'});

  @override
  State<PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<PasswordFields> {
  PasswordPolicy _policy = const PasswordPolicy();
  bool _hidden = true;
  bool _hiddenConfirmation = true;

  @override
  void initState() {
    super.initState();
    PasswordPolicy.load(() => context.api.get('/password-policy')).then((policy) {
      if (mounted) setState(() => _policy = policy);
    });
  }

  Widget _eye(bool hidden, VoidCallback toggle) =>
      IconButton(tooltip: hidden ? 'Ver la contraseña' : 'Ocultar la contraseña', icon: Icon(hidden ? Icons.visibility : Icons.visibility_off), onPressed: toggle);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextFormField(
        controller: widget.password,
        obscureText: _hidden,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'p. ej. Ruta.2026',
          prefixIcon: const Icon(Icons.lock_outline),
          errorMaxLines: 3,
          suffixIcon: _eye(_hidden, () => setState(() => _hidden = !_hidden)),
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: _policy.validate,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: widget.confirmation,
        obscureText: _hiddenConfirmation,
        decoration: InputDecoration(
          labelText: 'Repita la contraseña',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: _eye(_hiddenConfirmation, () => setState(() => _hiddenConfirmation = !_hiddenConfirmation)),
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (value) => (value ?? '').isEmpty
            ? 'Repita la contraseña'
            : value != widget.password.text
                ? 'Las contraseñas no coinciden'
                : null,
      ),
    ]);
  }
}
