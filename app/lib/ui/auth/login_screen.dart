import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/storage.dart';
import '../../services/app_info.dart';
import '../../services/app_updates.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/connection_dot.dart';
import 'access_recovery_screen.dart';
import 'register_screen.dart';
import 'server_screen.dart';

/// Inicio de sesión (docs/11 §11.50, §11.51 y §11.54; maqueta G18_login):
/// botón «Servidor» rojo si no hay servidor (y diálogo «Falta el servidor»
/// al intentar operar sin él); Entrar, Olvidé usuario/contraseña y
/// Registrarme. Con una actualización obligatoria pendiente no deja entrar
/// hasta instalarla (lo recuerda sin conexión).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _hidden = true;
  String? _error;
  AppUpdate? _mandatory;
  String _version = '';

  @override
  void initState() {
    super.initState();
    Storage.lastLogin().then((value) {
      if (value != null && mounted && _username.text.isEmpty) setState(() => _username.text = value);
    });
    Storage.getBool(Session.rememberKey, fallback: true).then((v) {
      if (mounted) setState(() => _remember = v);
    });
    AppInfo.label().then((v) {
      if (mounted) setState(() => _version = v);
    });
    _checkUpdate();
    context.read<Session>().connection.check();
  }

  /// La obligación guardada y, con conexión, la comprobación en el servidor.
  Future<void> _checkUpdate() async {
    final api = context.read<Session>().api;
    final saved = await AppUpdates.mandatory();
    if (mounted) setState(() => _mandatory = saved);
    if (!api.hasServer) return;
    try {
      final update = await AppUpdates.check(api);
      if (mounted) setState(() => _mandatory = update != null && update.mandatory ? update : null);
    } catch (_) {
      // Sin conexión: vale lo guardado.
    }
  }

  Future<bool> _needServer() async {
    if (context.read<Session>().api.hasServer) return false;
    if (await showMissingServer(context) && mounted) await _openServer();
    return true;
  }

  Future<void> _openServer() async {
    await push(context, const ServerScreen());
    if (mounted) {
      setState(() {});
      _checkUpdate();
    }
  }

  Future<void> _login() async {
    final session = context.read<Session>();
    if (await _needServer()) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await session.login(_username.text, _password.text, remember: _remember);
    } on ApiException catch (error) {
      if (error.statusCode == 426) {
        await _checkUpdate();
        return;
      }
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasServer = context.watch<Session>().api.hasServer;
    final mandatory = _mandatory;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                const Spacer(),
                hasServer
                    ? OutlinedButton.icon(onPressed: _openServer, icon: const Icon(Icons.dns_outlined), label: const Text('Servidor'))
                    : FilledButton.icon(
                        onPressed: _openServer, style: FilledButton.styleFrom(backgroundColor: red), icon: const Icon(Icons.dns_outlined), label: const Text('Servidor')),
                const ConnectionDot(onBar: false),
              ]),
            ),
            const SizedBox(height: 28),
            const Center(child: AppIcon(size: 110)),
            const SizedBox(height: 12),
            Center(child: Text('MiRuta', style: t.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.primary))),
            const SizedBox(height: 20),
            if (mandatory != null) _MandatoryUpdate(update: mandatory, onChecked: _checkUpdate),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Escriba su usuario' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextFormField(
                controller: _password,
                obscureText: _hidden,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Ver la contraseña' : 'Ocultar la contraseña',
                    icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                ),
                onFieldSubmitted: (_) => _login(),
                validator: (v) => (v ?? '').isEmpty ? 'Escriba su contraseña' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                title: const Text('Recordar contraseña'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(_error!, style: TextStyle(color: t.colorScheme.error))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: mandatory != null || !hasServer
                  ? SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                          onPressed: mandatory != null ? null : _needServer, icon: const Icon(Icons.login), label: const Text('Entrar', style: TextStyle(fontSize: 16))))
                  : BusyButton(onPressed: _login, icon: Icons.login, label: 'Entrar'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await _needServer() || !context.mounted) return;
                    push(context, const AccessRecoveryScreen());
                  },
                  style: FilledButton.styleFrom(backgroundColor: t.colorScheme.secondary, foregroundColor: Colors.black),
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Olvidé usuario/contraseña', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: mandatory != null
                      ? null
                      : () async {
                          if (await _needServer() || !context.mounted) return;
                          push(context, const RegisterScreen());
                        },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Registrarme', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(child: Text(_version, style: t.textTheme.bodySmall)),
          ]),
        ),
      ),
    );
  }
}

/// Aviso de actualización obligatoria con «Descargar e instalar».
class _MandatoryUpdate extends StatefulWidget {
  final AppUpdate update;
  final Future<void> Function() onChecked;

  const _MandatoryUpdate({required this.update, required this.onChecked});

  @override
  State<_MandatoryUpdate> createState() => _MandatoryUpdateState();
}

class _MandatoryUpdateState extends State<_MandatoryUpdate> {
  String? _progress;

  Future<void> _install() async {
    var update = widget.update;
    if (update.downloadUrl == null) {
      try {
        update = await AppUpdates.check(context.read<Session>().api) ?? update;
      } catch (error) {
        if (mounted) showError(context, error);
        return;
      }
    }
    if (update.downloadUrl == null) {
      if (mounted) showMessage(context, 'Conéctese al servidor para descargar la versión nueva.');
      return;
    }
    setState(() => _progress = 'Descargando…');
    AppUpdates.install(update).listen((event) {
      if (!mounted) return;
      setState(() {
        _progress = switch (event.status) {
          OtaStatus.DOWNLOADING => 'Descargando ${event.value ?? ''} %',
          OtaStatus.INSTALLING || OtaStatus.INSTALLATION_DONE => 'Abriendo el instalador…',
          OtaStatus.CHECKSUM_ERROR => 'El archivo descargado no es correcto. Vuelva a intentarlo.',
          _ => 'No se pudo descargar: ${event.value ?? ''}',
        };
      });
    }, onError: (Object error) {
      if (mounted) setState(() => _progress = 'No se pudo descargar la actualización.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final u = widget.update;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: red.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(side: const BorderSide(color: red), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.system_update, color: red),
            const SizedBox(width: 10),
            Expanded(child: Text('Actualización obligatoria', style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text('Para seguir usando MiRuta instale la versión ${u.versionName.isEmpty ? 'nueva' : u.versionName}${u.sizeBytes > 0 ? ' (${u.sizeLabel})' : ''}. Hasta entonces no puede entrar.'),
          if (u.notes != null && u.notes!.isNotEmpty) ...[const SizedBox(height: 6), Text(u.notes!, style: t.textTheme.bodySmall)],
          if (_progress != null) ...[const SizedBox(height: 6), Text(_progress!)],
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(onPressed: widget.onChecked, icon: const Icon(Icons.refresh), label: const Text('Comprobar')),
            const Spacer(),
            FilledButton.icon(onPressed: _install, icon: const Icon(Icons.download), label: const Text('Descargar e instalar')),
          ]),
        ]),
      ),
    );
  }
}
