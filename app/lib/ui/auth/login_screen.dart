import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/storage.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import 'access_recovery_screen.dart';
import 'activation_screen.dart';
import 'register_screen.dart';
import 'server_screen.dart';

/// Estado del servidor en el botón del pie (docs/09-repaso-pantallas.md §1).
enum _ServerStatus { none, checking, connected, disconnected }

/// Inicio de sesión (docs/09 §1). También se muestra cuando la sesión está
/// bloqueada y hay que volver a escribir la contraseña.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);

  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  String? _error;
  _ServerStatus _server = _ServerStatus.none;

  @override
  void initState() {
    super.initState();
    final session = context.session;
    Storage.lastLogin().then((login) {
      // Las versiones anteriores recordaban el carné: no sirve como usuario.
      if (login != null && RegExp(r'^\d+$').hasMatch(login)) login = null;
      // Sesión bloqueada: se muestra el usuario de la sesión aunque no se recuerde.
      if (login == null && session.state == SessionState.locked) login = session.me?.username;
      if (login != null && _user.text.isEmpty && mounted) setState(() => _user.text = login!);
    });
    _checkServer();
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Comprueba si el servidor guardado responde (al abrir y al volver de Servidor).
  Future<void> _checkServer() async {
    final api = context.api;
    if (!api.hasServer) {
      setState(() => _server = _ServerStatus.none);
      return;
    }
    setState(() => _server = _ServerStatus.checking);
    var status = _ServerStatus.connected;
    try {
      await ApiClient.probe(api.baseUrl);
    } catch (_) {
      status = _ServerStatus.disconnected;
    }
    if (mounted) setState(() => _server = status);
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

  Future<void> _openServer() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerScreen()));
    if (!mounted) return;
    setState(() => _error = null);
    await _checkServer();
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Widget _serverButton() {
    final (String label, IconData icon, Color background, Color foreground) = switch (_server) {
      _ServerStatus.none => ('Indicar servidor', Icons.dns, orange, navy),
      _ServerStatus.checking => ('Comprobando el servidor…', Icons.dns, Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.onSurface),
      _ServerStatus.connected => ('Conectado al servidor', Icons.cloud_done_outlined, _green, Colors.white),
      _ServerStatus.disconnected => ('Desconectado del servidor', Icons.cloud_off_outlined, _red, Colors.white),
    };
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: background, foregroundColor: foreground),
      onPressed: _openServer,
      icon: _server == _ServerStatus.checking ? const BusyIndicator() : Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
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
                const Center(child: AppIcon(size: 88)),
                const SizedBox(height: 12),
                Text('MiRuta', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Nombre de usuario', hintText: 'p. ej. ana.perez', prefixIcon: Icon(Icons.person_outline)),
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Escriba su nombre de usuario' : null,
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
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => value == null || value.isEmpty ? 'Escriba su contraseña' : null,
                  onFieldSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                // Grupo 1: misma línea y mismo tamaño.
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: BusyButton(
                        onPressed: _login,
                        showErrors: false,
                        icon: const Icon(Icons.login),
                        buttonStyle: FilledButton.styleFrom(backgroundColor: navy, foregroundColor: Colors.white),
                        child: const Text('Entrar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: orange, foregroundColor: navy),
                        onPressed: () => _open(const AccessRecoveryScreen()),
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: const Text('Olvidé algo'),
                      ),
                    ),
                  ]),
                ),
                const Divider(height: 32),
                FilledButton.tonalIcon(
                  onPressed: () => _open(const RegisterScreen()),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Registrarme por primera vez'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _open(const ActivationScreen()),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Me registró un superior'),
                ),
                const Divider(height: 32),
                _serverButton(),
                const SizedBox(height: 8),
                const DeveloperChatButton(),
                const SizedBox(height: 16),
                const AppVersionText(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
