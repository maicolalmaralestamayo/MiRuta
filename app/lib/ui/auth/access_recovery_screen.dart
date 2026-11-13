import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// «Olvidé usuario/contraseña» (docs/11 §11.7 y §11.51): olvidé el usuario, la contraseña o los dos,
/// con el carné de identidad y un teléfono. Solo el Administrador lo aprueba,
/// tras confirmarlo por una tercera vía. Al aprobarse, aquí se ve una sola vez
/// solo lo pedido (el usuario y/o una contraseña propuesta, que habrá que
/// cambiar al entrar).
class AccessRecoveryScreen extends StatefulWidget {
  const AccessRecoveryScreen({super.key});

  @override
  State<AccessRecoveryScreen> createState() => _AccessRecoveryScreenState();
}

class _AccessRecoveryScreenState extends State<AccessRecoveryScreen> {
  static const _storageKey = 'access_recovery_id';

  final _form = GlobalKey<FormState>();
  final _identityCard = TextEditingController();
  final _phone = TextEditingController(text: '+53 ');
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
      final recovery = (await context.api.get('/guest/access-recoveries/$_recoveryId', guest: true)).resource;
      if (mounted) setState(() => _recovery = recovery);
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
      showMessage(context, 'Marque qué olvidó.');
      return;
    }
    final recovery = (await context.api.post('/guest/access-recoveries', resourceData('access-recoveries', attributes: {
      'forgotUsername': _forgotUsername,
      'forgotPassword': _forgotPassword,
      'identityCard': _identityCard.text.trim(),
      'phone': _phone.text.trim(),
    }), guest: true)).resource;
    await Storage.setString(_storageKey, recovery.id);
    if (mounted) {
      setState(() {
        _recoveryId = recovery.id;
        _recovery = recovery;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Olvidé usuario/contraseña'), leading: const BackButton()),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(key: _form, child: _recovery == null ? _requestForm() : _status()),
    );
  }

  Widget _requestForm() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('El Administrador comprobará sus datos y le llamará o escribirá a este teléfono antes de aprobar la solicitud.'),
      const Divider(height: 32),
      const Text('¿Qué olvidó?'),
      CheckboxListTile(value: _forgotUsername, onChanged: (v) => setState(() => _forgotUsername = v ?? false), title: const Text('Mi nombre de usuario')),
      CheckboxListTile(value: _forgotPassword, onChanged: (v) => setState(() => _forgotPassword = v ?? false), title: const Text('Mi contraseña')),
      const SizedBox(height: 8),
      TextFormField(
        controller: _identityCard,
        decoration: const InputDecoration(labelText: 'Carné de identidad', hintText: 'p. ej. 85031512345', prefixIcon: Icon(Icons.badge_outlined)),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(IdentityCard.length)],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: IdentityCard.validate,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phone,
        decoration: const InputDecoration(labelText: 'Teléfono', hintText: 'p. ej. +53 5 123 4567', prefixIcon: Icon(Icons.phone_outlined)),
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) => RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v?.trim() ?? '') && (v ?? '').replaceAll(RegExp(r'\D'), '').length >= 7
            ? null
            : 'Escriba un teléfono válido, con el código del país (p. ej. +53 5 123 4567)',
      ),
      const SizedBox(height: 20),
      BusyButton(onPressed: _request, icon: Icons.send, label: 'Enviar solicitud'),
    ]);
  }

  Widget _status() {
    final recovery = _recovery!;
    final status = recovery.string('status');
    final username = recovery.string('username');
    final password = recovery.string('password');

    if (status == 'pending') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.hourglass_top),
            title: Text('Solicitud enviada'),
            subtitle: Text('El Administrador comprobará sus datos y se pondrá en contacto con usted. Cuando la apruebe, vuelva a esta pantalla.'),
          ),
        ),
        const SizedBox(height: 12),
        BusyButton(onPressed: _refresh, icon: Icons.refresh, label: 'Comprobar la solicitud', outlined: true),
        TextButton.icon(onPressed: _forget, icon: const Icon(Icons.add), label: const Text('Hacer otra solicitud')),
      ]);
    }

    if (status == 'approved' || (status == 'completed' && (username != null || password != null))) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Solicitud aprobada'))),
        if (username != null) ...[
          const SizedBox(height: 12),
          const Text('Su nombre de usuario es:'),
          SelectableText(username, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
        if (password != null) ...[
          const SizedBox(height: 12),
          const Text('Su contraseña nueva es:'),
          SelectableText(password, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Al entrar con ella tendrá que elegir una contraseña propia.'),
        ],
        if (username != null || password != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: [?username, ?password].join('\n'))),
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          const SizedBox(height: 4),
          Text('Anótelo ahora: solo se muestra esta vez.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await _forget();
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.login),
          label: const Text('Ir a iniciar sesión'),
        ),
      ]);
    }

    final message = const {
          'rejected': 'El Administrador rechazó la solicitud. Si cree que es un error, hable con el Administrador.',
          'expired': 'La solicitud caducó sin respuesta. Puede hacer otra.',
          'completed': 'Esta solicitud ya terminó.',
        }[status] ??
        'La solicitud ya no está abierta.';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(message))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _forget, icon: const Icon(Icons.add), label: const Text('Hacer otra solicitud')),
    ]);
  }
}
