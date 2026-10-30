import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/card_number.dart';
import '../../core/json_api.dart';
import '../widgets/common.dart';

/// Contraseña olvidada: 1) pedir el código con el carné y un teléfono con
/// WhatsApp; 2) entrar con el código que envía el Administrador.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialCard;

  const ForgotPasswordScreen({super.key, this.initialCard = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _requestForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  late final _card = TextEditingController(text: widget.initialCard);
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _requested = false;
  String? _error;

  Future<void> _request() async {
    if (!_requestForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.api.post('/password-resets', resourceData('password-resets', attributes: {
        'cardNumber': _card.text.trim(),
        'phone': _phone.text.trim(),
      }), auth: false);
      setState(() => _requested = true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterWithCode() async {
    if (!_codeForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.loginWithResetCode(_card.text.trim(), _code.text.trim());
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardField = TextFormField(
      controller: _card,
      decoration: const InputDecoration(labelText: 'Carné de identidad'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
      validator: validateCard,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Contraseña olvidada')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('1. Pide un código', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('El Administrador te lo enviará por WhatsApp al número que indiques.'),
        const SizedBox(height: 12),
        Form(
          key: _requestForm,
          child: Column(children: [
            cardField,
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Teléfono con WhatsApp', helperText: 'Con el código del país, p. ej. +53 5 123 4567'),
              keyboardType: TextInputType.phone,
              validator: (v) => RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v?.trim() ?? '') ? null : 'Escribe un número de teléfono válido',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(onPressed: _busy ? null : _request, child: const Text('Pedir código')),
            ),
          ]),
        ),
        if (_requested)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('Solicitud enviada'),
              subtitle: Text('Cuando el Administrador te escriba por WhatsApp, entra el código aquí abajo.'),
            ),
          ),
        const Divider(height: 40),
        Text('2. Entra con el código', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Después tendrás que elegir una contraseña nueva.'),
        const SizedBox(height: 12),
        Form(
          key: _codeForm,
          child: Column(children: [
            if (!_requested) ...[cardField, const SizedBox(height: 12)],
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Código', hintText: 'XXXX-XXXX'),
              textCapitalization: TextCapitalization.characters,
              validator: (v) => (v?.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length ?? 0) == 8 ? null : 'El código tiene 8 caracteres',
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _enterWithCode, child: const Text('Entrar'))),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
