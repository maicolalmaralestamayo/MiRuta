import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/card_number.dart';
import '../../core/username.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _card = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();

  /// Mientras no lo toque, el usuario se propone a partir del nombre.
  bool _usernameEdited = false;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  List<Rank> _ranks = [];
  String? _rankId;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _loadRanks();
  }

  Future<void> _loadRanks() async {
    try {
      final resources = await context.api.getAll('/ranks', query: {'sort': 'precedence'});
      setState(() => _ranks = resources.map(Rank.from).toList());
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.register(
        cardNumber: _card.text.trim(),
        username: _username.text.trim(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        rankId: _rankId!,
        password: _password.text,
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _suggestUsername() {
    if (_usernameEdited) return;
    _username.text = _firstName.text.trim().isEmpty && _lastName.text.trim().isEmpty
        ? ''
        : Username.suggest(_firstName.text, _lastName.text);
  }

  @override
  Widget build(BuildContext context) {
    final card = CardNumber.tryParse(_card.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Registro')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _card,
            decoration: InputDecoration(
              labelText: 'Carné de identidad',
              helperText: card == null ? 'Solo tú y el Administrador podrán verlo' : 'Sexo: ${card.sex == 'F' ? 'femenino' : 'masculino'}',
              errorText: _error?.fieldError('/cardNumber'),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            validator: validateCard,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: 'Nombre'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe tu nombre' : null,
            onChanged: (_) => _suggestUsername(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: 'Apellidos'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty ? 'Escribe tus apellidos' : null,
            onChanged: (_) => _suggestUsername(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _username,
            decoration: InputDecoration(
              labelText: 'Usuario',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: 'Con él entrarás a la app. Puedes cambiarlo luego en Mi perfil',
              helperMaxLines: 2,
              errorText: _error?.fieldError('/username'),
            ),
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
            validator: validateUsername,
            onChanged: (_) => _usernameEdited = true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _rankId,
            decoration: const InputDecoration(labelText: 'Jerarquía'),
            items: [for (final rank in _ranks) DropdownMenuItem(value: rank.id, child: Text(rank.name))],
            onChanged: (value) => setState(() => _rankId = value),
            validator: (v) => v == null ? 'Elige tu jerarquía' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña', helperText: 'Al menos 8 caracteres'),
            validator: (v) => v == null || v.length < 8 ? 'Al menos 8 caracteres' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmation,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repite la contraseña'),
            validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _register, child: const Text('Registrarme')),
        ]),
      ),
    );
  }
}
