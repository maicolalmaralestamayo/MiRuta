import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import '../guest/developer_chat_screen.dart';
import '../widgets/common.dart';
import 'entity_field.dart';
import 'password_fields.dart';

/// "No puedo entrar" (docs/08-version-2.md §8.6): olvidé el usuario, la
/// contraseña o los dos. El Administrador lo verifica por su cuenta y, si lo
/// aprueba, aquí mismo se ve el usuario o se elige una contraseña nueva.
class AccessRecoveryScreen extends StatefulWidget {
  const AccessRecoveryScreen({super.key});

  @override
  State<AccessRecoveryScreen> createState() => _AccessRecoveryScreenState();
}

class _AccessRecoveryScreenState extends State<AccessRecoveryScreen> {
  static const _storageKey = 'access_recovery_id';

  final _form = GlobalKey<FormState>();
  final _abbreviation = TextEditingController();
  final _pass = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _forgotUsername = false;
  bool _forgotPassword = true;
  String? _recoveryId;
  Resource? _recovery;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Storage.getString(_storageKey).then((id) {
      if (!mounted) return;
      setState(() {
        _recoveryId = id;
        _loading = id != null;
      });
      if (id != null) _refresh();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_recoveryId != null && _recovery?.string('status') == 'pending') _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final document = await context.api.get('/guest/access-recoveries/$_recoveryId', guest: true);
      if (mounted) setState(() => _recovery = document.resource);
    } on ApiException catch (error) {
      if (error.statusCode == 404) await _forget();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forget() async {
    await Storage.setString(_storageKey, null);
    if (mounted) {
      setState(() {
        _recoveryId = null;
        _recovery = null;
      });
    }
  }

  Future<void> _request() async {
    if (!_form.currentState!.validate()) return;
    if (!_forgotUsername && !_forgotPassword) {
      showMessage(context, 'Marca qué olvidaste.');
      return;
    }
    final document = await context.api.post('/guest/access-recoveries', resourceData('access-recoveries', attributes: {
      'forgotUsername': _forgotUsername,
      'forgotPassword': _forgotPassword,
      'entityAbbreviation': _abbreviation.text.trim(),
      'pass': int.parse(_pass.text),
      'phone': _phone.text.trim(),
    }), guest: true);
    await Storage.setString(_storageKey, document.resource.id);
    if (mounted) {
      setState(() {
        _recoveryId = document.resource.id;
        _recovery = document.resource;
      });
    }
  }

  Future<void> _setPassword() async {
    if (!_form.currentState!.validate()) return;
    await context.session.recoverWithNewPassword(_recoveryId!, _password.text);
    await Storage.setString(_storageKey, null);
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('No puedo entrar'), actions: const [DeveloperChatAction()]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(key: _form, child: _recovery == null ? _requestForm() : _status()),
    );
  }

  Widget _requestForm() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('¿Qué olvidaste?'),
      CheckboxListTile(value: _forgotUsername, onChanged: (v) => setState(() => _forgotUsername = v ?? false), title: const Text('Mi usuario')),
      CheckboxListTile(value: _forgotPassword, onChanged: (v) => setState(() => _forgotPassword = v ?? false), title: const Text('Mi contraseña')),
      const SizedBox(height: 8),
      const Text('El Administrador comprobará tus datos y te llamará o escribirá a este teléfono antes de aprobar la solicitud.'),
      const SizedBox(height: 16),
      EntityAbbreviationField(controller: _abbreviation, guest: true),
      const SizedBox(height: 12),
      PassField(controller: _pass),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phone,
        decoration: const InputDecoration(labelText: 'Teléfono', helperText: 'Con el código del país, p. ej. +53 5 123 4567', prefixIcon: Icon(Icons.phone_outlined)),
        keyboardType: TextInputType.phone,
        validator: (v) => RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v?.trim() ?? '') ? null : 'Escribe un teléfono válido',
      ),
      const SizedBox(height: 20),
      BusyButton(onPressed: _request, child: const Text('Enviar solicitud')),
    ]);
  }

  Widget _status() {
    final recovery = _recovery!;
    final status = recovery.string('status');
    final username = recovery.string('username');
    final forgotPassword = recovery.boolean('forgotPassword');

    if (status == 'pending') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.hourglass_top),
            title: Text('Solicitud enviada'),
            subtitle: Text('El Administrador comprobará tus datos y se pondrá en contacto contigo. Cuando la apruebe, vuelve a esta pantalla.'),
          ),
        ),
        const SizedBox(height: 12),
        BusyButton.tonal(onPressed: _refresh, icon: const Icon(Icons.refresh), child: const Text('Comprobar ahora')),
        TextButton(onPressed: _forget, child: const Text('Hacer otra solicitud')),
      ]);
    }

    if (status == 'approved') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Solicitud aprobada'))),
        if (username != null) ...[
          const SizedBox(height: 12),
          const Text('Tu usuario es:'),
          SelectableText(username, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
        if (forgotPassword) ...[
          const SizedBox(height: 16),
          const Text('Elige tu contraseña nueva:'),
          const SizedBox(height: 8),
          PasswordFields(password: _password, confirmation: _confirmation, label: 'Contraseña nueva', personal: () => [?username]),
          const SizedBox(height: 20),
          BusyButton(onPressed: _setPassword, child: const Text('Guardar y entrar')),
        ] else ...[
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await _forget();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Ir a iniciar sesión'),
          ),
        ],
      ]);
    }

    final message = const {
          'rejected': 'El Administrador rechazó la solicitud. Si crees que es un error, escríbele desde "Hablar con el desarrollador".',
          'expired': 'La solicitud caducó sin respuesta. Puedes hacer otra.',
          'completed': 'Esta solicitud ya terminó.',
        }[status] ??
        'La solicitud ya no está abierta.';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(message))),
      const SizedBox(height: 12),
      FilledButton(onPressed: _forget, child: const Text('Hacer otra solicitud')),
    ]);
  }
}
