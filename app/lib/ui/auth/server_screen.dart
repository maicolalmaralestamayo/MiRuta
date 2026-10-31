import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/server_url.dart';
import '../../core/storage.dart';
import '../../services/installation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';

/// Dirección del servidor (docs/05-app.md §5.1). La app no trae ninguna: la
/// escribe el usuario la primera vez y puede cambiarla desde el inicio de
/// sesión. Antes de guardarla se comprueba que responde MiTransporte.
class ServerScreen extends StatefulWidget {
  /// Se llama con la dirección completa una vez guardada.
  final void Function(String url) onSaved;

  /// La primera vez no hay a dónde volver.
  final bool firstTime;

  const ServerScreen({super.key, required this.onSaved, this.firstTime = false});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _form = GlobalKey<FormState>();
  late final _address = TextEditingController(text: context.api.hasServer ? ServerUrl.short(context.api.baseUrl) : '');
  String? _error;

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final url = ServerUrl.normalize(_address.text)!;
    final api = context.api;
    try {
      await ApiClient.probe(url);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (url != api.baseUrl) {
      // La instalación quedó registrada en el servidor anterior.
      await Installation.forget();
      await Storage.setApiUrl(url);
      api.setBaseUrl(url);
    }
    widget.onSaved(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.firstTime ? null : AppBar(title: const Text('Servidor')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.firstTime) ...[
                  const Center(child: AppIcon(size: 88)),
                  const SizedBox(height: 12),
                  Text('MiTransporte', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 24),
                ],
                Text('¿A qué servidor se conecta la app?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Escribe la dirección que te dio quien administra MiTransporte en tu empresa, por ejemplo transporte.miempresa.com.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Dirección del servidor', prefixIcon: Icon(Icons.dns_outlined)),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  validator: (value) => ServerUrl.normalize(value ?? '') == null ? 'Escribe una dirección válida' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                BusyButton(onPressed: _save, showErrors: false, child: const Text('Conectar')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
