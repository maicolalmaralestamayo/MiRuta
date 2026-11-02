import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/server_url.dart';
import '../../core/storage.dart';
import '../../services/installation.dart';
import '../admin/server_maintenance_screen.dart';
import '../widgets/common.dart';

/// Dirección del servidor (docs/09-repaso-pantallas.md §2). Se abre desde el
/// botón del servidor del inicio de sesión. Se usa el protocolo elegido (sin
/// probar otros) y, antes de guardar, se comprueba que responde MiRuta. Si
/// el servidor redirige (p. ej. de http a https), se guarda la dirección a
/// la que se llegó.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  String _protocol = ServerUrl.defaultProtocol;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Con una dirección ya guardada se muestran su protocolo y su dirección.
    if (context.api.hasServer) {
      final saved = ServerUrl.split(context.api.baseUrl);
      _protocol = saved.protocol ?? ServerUrl.defaultProtocol;
      _address.text = saved.address;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// Si se pega una URL completa, el selector toma su protocolo y se quita
  /// de la dirección.
  void _onChanged(String value) {
    final parts = ServerUrl.split(value);
    if (parts.protocol == null) return;
    final rest = value.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    setState(() => _protocol = parts.protocol!);
    _address.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final api = context.api;
    final String url;
    try {
      url = await ApiClient.probe(ServerUrl.build(_protocol, _address.text)!);
    } on ApiException catch (error) {
      setState(() => _error = error.code == 'NOT_MITRANSPORTE' ? error.message : ApiClient.unreachableMessage);
      return;
    }
    if (url != api.baseUrl) {
      // La instalación quedó registrada en el servidor anterior.
      await Installation.forget();
      await Storage.setApiUrl(url);
      api.setBaseUrl(url);
    }
    if (!mounted) return;
    showMessage(context, ServerUrl.isPlain(url) ? 'Conectado al servidor (sin cifrar, por http).' : 'Conectado al servidor.');
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
          const Text('Elija el protocolo de conexión e indique la dirección del servidor que le facilitó el administrador de la aplicación.'),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 116,
              child: DropdownButtonFormField<String>(
                initialValue: _protocol,
                key: ValueKey(_protocol),
                decoration: const InputDecoration(labelText: 'Protocolo'),
                items: [for (final protocol in ServerUrl.protocols) DropdownMenuItem(value: protocol, child: Text(protocol))],
                onChanged: (value) => setState(() => _protocol = value ?? ServerUrl.defaultProtocol),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Dirección del servidor', hintText: 'p. ej. transporte.ejemplo.org', errorMaxLines: 3),
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: _onChanged,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Escriba la dirección del servidor'
                    : ServerUrl.isValid(value!, protocol: _protocol)
                        ? null
                        : 'Escriba una dirección válida, sin espacios (p. ej. transporte.ejemplo.org)',
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(onPressed: _connect, showErrors: false, icon: const Icon(Icons.cloud_sync_outlined), child: const Text('Conectar al servidor')),
          // Para quien administra el servidor: instalarlo o arreglarlo sin
          // iniciar sesión, con la clave de mantenimiento.
          if (context.api.hasServer) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              icon: const Icon(Icons.dns_outlined),
              label: const Text('Mantenimiento del servidor'),
              onPressed: () => ServerMaintenanceScreen.openWithKey(context, context.api),
            ),
          ],
        ]),
      ),
    );
  }
}
