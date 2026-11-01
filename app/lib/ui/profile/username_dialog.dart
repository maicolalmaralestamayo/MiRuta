import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/username.dart';
import '../widgets/common.dart';

/// Cambiar el usuario con el que se entra a la app. Devuelve true si cambió.
Future<bool> editUsername(BuildContext context) async {
  final changed = await showDialog<bool>(context: context, builder: (_) => const _UsernameDialog());
  return changed ?? false;
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
    // Mientras guarda, el botón muestra el indicador de carga.
    try {
      await context.session.changeUsername(_controller.text);
      if (mounted) {
        showMessage(context, 'Nombre de usuario cambiado. Desde ahora entre con «${Username.normalize(_controller.text)}».');
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
      title: const Text('Nombre de usuario'),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nombre de usuario',
            hintText: 'pedro.perez',
            errorText: _error,
            errorMaxLines: 3,
          ),
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(Username.maxLength)],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validateUsername,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const BusyIndicator() : const Icon(Icons.save),
          label: const Text('Guardar nombre de usuario'),
        ),
      ],
    );
  }
}
