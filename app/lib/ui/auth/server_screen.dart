import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/server_url.dart';
import '../../core/storage.dart';
import '../../services/installation.dart';
import '../widgets/common.dart';

/// Dirección del servidor (docs/05-app.md §5.2). Se abre desde el botón
/// «Servidor» de la bienvenida. Antes de guardarla se comprueba que responde
/// MiTransporte; sin protocolo se prueba HTTPS y, si no, HTTP.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

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
    final api = context.api;
    String? url;
    ApiException? failure;
    for (final candidate in ServerUrl.candidates(_address.text)) {
      try {
        await ApiClient.probe(candidate);
        url = candidate;
        break;
      } on ApiException catch (error) {
        // Se informa del primer fallo que no sea de conexión (es más útil).
        if (failure == null || failure.code == 'NETWORK_ERROR') failure = error;
      }
    }
    if (url == null) {
      setState(() => _error = failure?.message);
      return;
    }
    if (url != api.baseUrl) {
      // La instalación quedó registrada en el servidor anterior.
      await Installation.forget();
      await Storage.setApiUrl(url);
      api.setBaseUrl(url);
    }
    if (!mounted) return;
    showMessage(context, ServerUrl.isPlain(url) ? 'Conectado (sin cifrar, por http).' : 'Conectado.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Servidor')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Escribe la dirección del servidor de MiTransporte que te dio quien administra la app en tu empresa, por ejemplo transporte.miempresa.com.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección del servidor', prefixIcon: Icon(Icons.dns_outlined)),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            validator: (value) => ServerUrl.isValid(value ?? '') ? null : 'Escribe una dirección válida',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _save, showErrors: false, child: const Text('Conectar')),
        ]),
      ),
    );
  }
}
