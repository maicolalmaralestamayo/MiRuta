import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../services/templates.dart';
import '../widgets/common.dart';

/// Mantenimiento del servidor, para hospedajes sin acceso por SSH: ver su
/// estado, instalar o actualizar la base de datos, ejecutar las tareas
/// programadas, limpiar la caché y leer el registro de errores.
///
/// Lo usa el Administrador con su sesión o, sin sesión (servidor recién
/// instalado o con problemas), cualquiera con la clave de mantenimiento
/// del servidor ([maintenanceKey]).
class ServerMaintenanceScreen extends StatefulWidget {
  final ApiClient api;
  final String? maintenanceKey;

  const ServerMaintenanceScreen({super.key, required this.api, this.maintenanceKey});

  /// Pide la clave de mantenimiento y abre la pantalla.
  static Future<void> openWithKey(BuildContext context, ApiClient api) async {
    final key = await promptText(context, 'Clave de mantenimiento', label: 'Clave', required: true);
    if (key == null || key.isEmpty || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ServerMaintenanceScreen(api: api, maintenanceKey: key)));
  }

  @override
  State<ServerMaintenanceScreen> createState() => _ServerMaintenanceScreenState();
}

class _ServerMaintenanceScreenState extends State<ServerMaintenanceScreen> {
  final _view = GlobalKey<AsyncViewState<Resource>>();

  Map<String, String>? get _headers => widget.maintenanceKey == null ? null : {'X-Maintenance-Key': widget.maintenanceKey!};

  Future<Resource> _load() async => (await widget.api.get('/server-status', headers: _headers)).resource;

  Future<void> _run(String command, String title) async {
    final document = await widget.api.post('/maintenance-runs', resourceData('maintenance-runs', attributes: {'command': command}), headers: _headers);
    final result = document.resource.attributes;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [
          Icon(result['ok'] == true ? Icons.check_circle_outline : Icons.error_outline,
              color: result['ok'] == true ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ]),
        content: SingleChildScrollView(
          child: SelectableText(
            (result['output'] as String?)?.isNotEmpty == true ? result['output'] as String : 'Hecho.',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
    await _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mantenimiento del servidor')),
      body: AsyncView<Resource>(
        key: _view,
        load: _load,
        builder: (context, status, reload) => RefreshIndicator(
          onRefresh: reload,
          child: _StatusList(status: status.attributes, run: _run),
        ),
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  final Map<String, dynamic> status;
  final Future<void> Function(String command, String title) run;

  const _StatusList({required this.status, required this.run});

  static const _taskNames = {
    'trips:auto-complete': 'Dar por terminados los viajes',
    'trips:notify-delays': 'Avisos de inicio y de retraso',
    'chats:purge-trips': 'Borrar chats de viajes terminados',
    'chats:purge-expired': 'Borrar conversaciones vencidas',
    'workers:inactivity': 'Inactividad de los trabajadores',
    'access-recoveries:expire': 'Vencer las recuperaciones de acceso',
    'passwords:warn-expiry': 'Avisos de contraseña por caducar',
  };

  @override
  Widget build(BuildContext context) {
    final database = Map<String, dynamic>.from(status['database'] as Map? ?? {});
    final php = Map<String, dynamic>.from(status['php'] as Map? ?? {});
    final extensions = Map<String, dynamic>.from(status['extensions'] as Map? ?? {});
    final tasks = Map<String, dynamic>.from(status['tasks'] as Map? ?? {});
    final pending = (database['pendingMigrations'] as List? ?? []).length;
    final installed = database['installed'] == true;
    final connected = database['connected'] == true;
    final missing = [for (final entry in extensions.entries) if (entry.value != true && !const ['zip', 'gd'].contains(entry.key)) entry.key];

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const SectionTitle('Servidor'),
      _Check(ok: true, title: 'Versión del servidor', value: '${status['apiVersion'] ?? '?'}'),
      _Check(
        ok: status['phpSupported'] == true,
        title: 'PHP ${status['phpVersion']}',
        value: status['phpSupported'] == true ? 'Versión adecuada' : 'Pida al hospedaje una versión de PHP entre 7.2.5 y 8.0',
      ),
      _Check(ok: missing.isEmpty, title: 'Extensiones de PHP', value: missing.isEmpty ? 'Están todas' : 'Faltan: ${missing.join(', ')}'),
      _Check(ok: null, title: 'Tamaño máximo de subida', value: '${php['uploadMaxFilesize'] ?? '?'} (por petición: ${php['postMaxSize'] ?? '?'})'),
      _Check(ok: null, title: 'Hora del servidor', value: '${_when(status['serverTime'])} · ${status['timezone']}'),

      const SectionTitle('Base de datos'),
      _Check(ok: connected, title: connected ? 'Conectada' : 'No conecta', value: connected ? null : '${database['error'] ?? ''}'),
      if (connected)
        _Check(
          ok: installed && pending == 0,
          title: !installed ? 'Sin instalar' : (pending == 0 ? 'Al día' : 'Faltan cambios por aplicar'),
          value: !installed ? 'Pulse «Instalar base de datos».' : (pending == 0 ? null : '${plural(pending, 'cambio pendiente', 'cambios pendientes')}. Pulse «Actualizar base de datos».'),
        ),

      const SectionTitle('Carpetas'),
      _folder('Carpeta de trabajo', status['storage']),
      _folder('Archivos subidos (fotos y APK)', status['uploads']),

      const SectionTitle('Tareas programadas'),
      _Check(
        ok: null,
        title: tasks['onRequests'] == true ? 'Se ejecutan con el uso de la app' : 'Se ejecutan con cron',
        value: tasks['lastCheck'] == null ? 'Aún no se han ejecutado' : 'Última revisión: ${_when(tasks['lastCheck'])}',
      ),
      for (final task in (tasks['list'] as List? ?? []).cast<Map>())
        _Check(
          ok: task['ok'] as bool?,
          dense: true,
          title: _taskNames[task['command']] ?? '${task['command']}',
          value: task['lastRun'] == null
              ? 'Nunca'
              : '${_when(task['lastRun'])}${task['error'] != null ? ' · ${task['error']}' : ''}',
        ),

      const SectionTitle('Acciones'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (connected && !installed)
            BusyButton(icon: const Icon(Icons.storage), onPressed: () => run('install', 'Instalar base de datos'), child: const Text('Instalar base de datos')),
          if (connected && installed)
            BusyButton(
              style: pending > 0 ? BusyButtonStyle.filled : BusyButtonStyle.tonal,
              icon: const Icon(Icons.upgrade),
              onPressed: () => run('migrate', 'Actualizar base de datos'),
              child: const Text('Actualizar base de datos'),
            ),
          const SizedBox(height: 8),
          if (installed)
            BusyButton.outlined(icon: const Icon(Icons.play_arrow), onPressed: () => run('run-tasks', 'Tareas pendientes'), child: const Text('Ejecutar tareas pendientes')),
          const SizedBox(height: 8),
          BusyButton.outlined(icon: const Icon(Icons.cleaning_services_outlined), onPressed: () => run('clear-cache', 'Limpiar caché'), child: const Text('Limpiar caché')),
          const SizedBox(height: 8),
          BusyButton.outlined(icon: const Icon(Icons.receipt_long_outlined), onPressed: () => run('log', 'Registro de errores'), child: const Text('Ver registro de errores')),
        ]),
      ),
    ]);
  }

  static String _when(Object? iso) {
    final date = DateTime.tryParse('${iso ?? ''}');
    return date == null ? '?' : formatDateTime(date.toLocal());
  }

  Widget _folder(String title, Object? data) {
    final folder = Map<String, dynamic>.from(data as Map? ?? {});
    final writable = folder['writable'] == true;
    return _Check(
      ok: writable,
      title: title,
      value: writable ? '${folder['path']}' : '${folder['path']}\nNo se puede escribir: con FileZilla dé permisos 775 (o 777) a esta carpeta.',
    );
  }
}

class _Check extends StatelessWidget {
  final bool? ok;
  final String title;
  final String? value;
  final bool dense;

  const _Check({required this.ok, required this.title, this.value, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: dense,
      leading: Icon(
        ok == null ? Icons.info_outline : (ok! ? Icons.check_circle_outline : Icons.error_outline),
        color: ok == null ? scheme.onSurfaceVariant : (ok! ? Colors.green.shade700 : scheme.error),
      ),
      title: Text(title),
      subtitle: value == null || value!.isEmpty ? null : Text(value!),
    );
  }
}
