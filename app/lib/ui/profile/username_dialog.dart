import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../../services/session.dart';
import '../widgets/common.dart';

/// Cambiar el usuario con el que se entra a la app. Devuelve true si cambió.
Future<bool> editUsername(BuildContext context) async {
  final changed = await showDialog<bool>(context: context, builder: (_) => const _UsernameDialog());
  return changed ?? false;
}

/// Aviso a quien entró con el carné: a partir de ahora puede usar su usuario.
Future<void> showUsernameHint(BuildContext context, Session session) async {
  session.showUsernameHint = false;
  final username = session.me?.username;
  if (username == null) return;
  final change = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.person_outline),
      title: const Text('Ya tienes usuario'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Ya no hace falta escribir el carné para entrar. Tu usuario es:'),
        const SizedBox(height: 12),
        SelectableText(username, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Puedes cambiarlo ahora o cuando quieras en Mi perfil.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cambiarlo')),
        FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Entendido')),
      ],
    ),
  );
  if (change == true && context.mounted) await editUsername(context);
}

class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog();

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: context.me.username ?? '');
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.changeUsername(_controller.text);
      if (mounted) {
        showMessage(context, 'Usuario cambiado. Desde ahora entra con «${Username.normalize(_controller.text)}».');
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.fieldError('/username') ?? error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mi usuario'),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Usuario',
            helperText: 'Letras sin tilde, números, punto o guion bajo',
            errorText: _error,
            errorMaxLines: 3,
          ),
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(30)],
          validator: validateUsername,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
