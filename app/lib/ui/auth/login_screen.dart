import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/storage.dart';
import '../widgets/common.dart';
import 'forgot_password_screen.dart';
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
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Storage.lastLogin().then((login) {
      if (login != null && mounted) setState(() => _user.text = login);
    });
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.login(_user.text.trim(), _password.text);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _server() async {
    final url = await promptText(context, 'Servidor', label: 'Dirección de la API', initial: context.api.baseUrl);
    if (url == null || url.isEmpty) return;
    await Storage.setApiUrl(url);
    if (mounted) context.api.setBaseUrl(url);
  }

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
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline),
                    helperText: 'Si no lo recuerdas, también puedes entrar con tu carné',
                  ),
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
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialLogin: _user.text))),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('¿No tienes cuenta? Regístrate'),
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
