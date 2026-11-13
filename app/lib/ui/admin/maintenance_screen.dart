import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/json_api.dart';
import '../../services/session.dart';
import '../navigation.dart';
import '../widgets/actions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/data_view.dart';

/// Mantenimiento del servidor (maqueta G18 n.º 21): todo lo que hay que
/// ejecutar en el servidor se hace con la API (docs/11 §11.55). Con la sesión
/// del Administrador o, sin sesión, con la clave de mantenimiento.
class MaintenanceScreen extends StatefulWidget {
  final String? maintenanceKey;

  const MaintenanceScreen({super.key, this.maintenanceKey});

  /// Pide la clave de mantenimiento y abre la pantalla (sin sesión).
  static Future<void> openWithKey(BuildContext context) async {
    final key = await promptText(context, 'Clave de mantenimiento', label: 'Clave', required: true, accept: 'Entrar', icon: Icons.key);
    if (key == null || key.isEmpty || !context.mounted) return;
    await push(context, MaintenanceScreen(maintenanceKey: key));
  }

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _view = GlobalKey<DataViewState<Map<String, dynamic>>>();

  Map<String, String>? get _headers => widget.maintenanceKey == null ? null : {'X-Maintenance-Key': widget.maintenanceKey!};

  Future<Map<String, dynamic>> _load() async => (await context.read<Session>().api.get('/server-status', headers: _headers)).resource.attributes;

  Future<void> _run(String command, String title) async {
    final document = await context.read<Session>().api.post('/maintenance-runs', resourceData('maintenance-runs', attributes: {'command': command}), headers: _headers);
    final result = document.resource.attributes;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(result['ok'] == true ? Icons.check_circle_outline : Icons.error_outline, color: result['ok'] == true ? green : red),
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText((result['output'] as String?)?.isNotEmpty == true ? result['output'] as String : 'Hecho.', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('Cerrar'))],
      ),
    );
    await _view.currentState?.reload();
  }

  static String _when(Object? iso) {
    final date = DateTime.tryParse('${iso ?? ''}');
    return date == null ? 'nunca' : formatDateTime(date);
  }

  void _details(String title, List<String> lines) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.info_outline, size: 32),
          title: Text(title, textAlign: TextAlign.center),
          content: SingleChildScrollView(child: SelectableText(lines.join('\n'))),
          actions: [TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('Cerrar'))],
        ),
      );

  List<ActionItem> _actions() {
    final status = _view.currentState?.data;
    final database = Map<String, dynamic>.from(status?['database'] as Map? ?? {});
    final installed = database['installed'] == true;
    return [
      if (database['connected'] == true && !installed) ActionItem(Icons.storage, 'Instalar base de datos', () => _run('install', 'Instalar base de datos')),
      if (installed) ActionItem(Icons.upgrade, 'Actualizar base de datos', () => _run('migrate', 'Actualizar base de datos')),
      if (installed) ActionItem(Icons.play_arrow, 'Ejecutar tareas', () => _run('run-tasks', 'Tareas pendientes')),
      ActionItem(Icons.cleaning_services_outlined, 'Limpiar caché', () => _run('clear-cache', 'Limpiar caché')),
      ActionItem(Icons.receipt_long_outlined, 'Ver registro de errores', () => _run('log', 'Registro de errores')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Mantenimiento del servidor',
      tab: MainTab.more,
      actions: _actions,
      body: DataView<Map<String, dynamic>>(
        key: _view,
        load: _load,
        builder: (context, status, reload) {
          final database = Map<String, dynamic>.from(status['database'] as Map? ?? {});
          final php = Map<String, dynamic>.from(status['php'] as Map? ?? {});
          final extensions = Map<String, dynamic>.from(status['extensions'] as Map? ?? {});
          final tasks = Map<String, dynamic>.from(status['tasks'] as Map? ?? {});
          final list = [for (final t in (tasks['list'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
          final pending = (database['pendingMigrations'] as List? ?? const []).length;
          final missing = [for (final e in extensions.entries) if (e.value != true) e.key];
          final serverOk = status['phpSupported'] == true && missing.isEmpty;
          final dbOk = database['connected'] == true && database['installed'] == true && pending == 0;
          final tasksOk = list.every((t) => t['ok'] != false);
          Widget state(bool ok, String good) => Chip2(ok ? good : 'Revisar', ok ? green : red);
          return ListView(padding: const EdgeInsets.only(bottom: 96), physics: const AlwaysScrollableScrollPhysics(), children: [
            FoldSection<int>(storageKey: 'mant.estado', title: 'Estado', items: const [0, 1, 2], paginate: false, builder: (i) {
              switch (i) {
                case 0:
                  return InfoCard(
                    images: const [CardImage(icon: Icons.dns_outlined)],
                    title: 'Servidor',
                    chip: state(serverOk, 'Bien'),
                    lines: ['En línea • PHP ${status['phpVersion']} • API ${status['apiVersion'] ?? '?'}', if (missing.isNotEmpty) 'Faltan extensiones: ${missing.join(', ')}'],
                    onTap: () => _details('Servidor', [
                      'Versión de la API: ${status['apiVersion']}',
                      'PHP ${status['phpVersion']}${status['phpSupported'] == true ? '' : ' (hace falta 8.2 o superior)'}',
                      'Subida máxima: ${php['uploadMaxFilesize']} (por petición ${php['postMaxSize']})',
                      'Memoria: ${php['memoryLimit']} • Tiempo máximo: ${php['maxExecutionTime']} s',
                      'Hora: ${_when(status['serverTime'])} (${status['timezone']})',
                      'Carpeta de trabajo: ${(status['storage'] as Map?)?['path']} ${(status['storage'] as Map?)?['writable'] == true ? '(se puede escribir)' : '(NO se puede escribir: permisos 775)'}',
                      'Archivos subidos: ${(status['uploads'] as Map?)?['path']} ${(status['uploads'] as Map?)?['writable'] == true ? '(se puede escribir)' : '(NO se puede escribir: permisos 775)'}',
                    ]),
                  );
                case 1:
                  return InfoCard(
                    images: const [CardImage(icon: Icons.storage)],
                    title: 'Base de datos',
                    chip: state(dbOk, 'Bien'),
                    lines: [
                      database['connected'] != true
                          ? 'No conecta: ${database['error'] ?? ''}'
                          : database['installed'] != true
                              ? 'Sin instalar: use Acciones → Instalar base de datos'
                              : (pending == 0 ? 'Conectada • al día' : 'Conectada • ${plural(pending, 'cambio pendiente', 'cambios pendientes')}'),
                    ],
                  );
                default:
                  return InfoCard(
                    images: const [CardImage(icon: Icons.schedule)],
                    title: 'Tareas programadas',
                    chip: state(tasksOk, 'Al día'),
                    lines: ['Última ejecución: ${_when(tasks['lastCheck'])}', tasks['onRequests'] == true ? 'Se ejecutan con el uso de la app' : 'Con «Ejecutar tareas»'],
                  );
              }
            }),
            FoldSection<Map<String, dynamic>>(
              storageKey: 'mant.tareas',
              title: 'Tareas',
              items: list,
              initiallyOpen: false,
              builder: (t) => InfoCard(
                images: [CardImage(icon: t['ok'] == false ? Icons.error_outline : Icons.task_alt)],
                title: '${t['command']}',
                lines: ['${t['frequency']} • última: ${_when(t['lastRun'])}', if (t['error'] != null) '${t['error']}'],
              ),
            ),
          ]);
        },
      ),
    );
  }
}
