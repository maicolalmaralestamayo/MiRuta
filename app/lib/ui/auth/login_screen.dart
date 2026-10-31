import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/storage.dart';
import '../guest/developer_chat_screen.dart';
import '../widgets/common.dart';
import 'access_recovery_screen.dart';
import 'activation_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Storage.lastLogin().then((login) {
      // Las versiones anteriores recordaban el carné: no sirve como usuario.
      if (login != null && !RegExp(r'^\d+$').hasMatch(login) && mounted) setState(() => _user.text = login);
    });
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.session.login(_user.text.trim(), _password.text);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _server() async {
    final url = await promptText(context, 'Servidor', label: 'Dirección de la API', initial: context.api.baseUrl);
    if (url == null || url.isEmpty) return;
    await Storage.setApiUrl(url);
    if (mounted) context.api.setBaseUrl(url);
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.directions_bus_filled, size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('MiTransporte', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Escribe tu usuario' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hidden,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hidden = !_hidden)),
                  ),
                  validator: (value) => value == null || value.isEmpty ? 'Escribe la contraseña' : null,
                  onFieldSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                BusyButton(onPressed: _login, showErrors: false, child: const Text('Entrar')),
                const SizedBox(height: 8),
                TextButton(onPressed: () => _open(const AccessRecoveryScreen()), child: const Text('No puedo entrar')),
                TextButton(onPressed: () => _open(const RegisterScreen()), child: const Text('¿No tienes cuenta? Créala')),
                TextButton(onPressed: () => _open(const ActivationScreen()), child: const Text('Ya me registró un superior')),
                const Divider(height: 24),
                TextButton.icon(
                  onPressed: () => _open(const GuestConversationsScreen()),
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Hablar con el desarrollador'),
                ),
                TextButton.icon(onPressed: _server, icon: const Icon(Icons.dns_outlined, size: 18), label: const Text('Servidor')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
