import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../services/app_updates.dart';
import '../widgets/common.dart';

/// Descarga e instalación de una versión nueva. Si es obligatoria, no se puede
/// cerrar: la versión instalada ya no puede usarse.
class UpdateScreen extends StatefulWidget {
  final AppUpdate update;

  const UpdateScreen({super.key, required this.update});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  StreamSubscription<OtaEvent>? _subscription;
  double? _progress;
  String? _status;
  bool _running = false;

  /// Solo Wi-Fi activado y con datos móviles: se avisa del tamaño antes.
  bool _mobileWarning = false;

  @override
  void initState() {
    super.initState();
    AppUpdates.shouldWarnMobileData().then((warn) {
      if (mounted) setState(() => _mobileWarning = warn);
    });
  }

  Future<void> _confirmAndStart() async {
    final update = widget.update;
    if (_mobileWarning &&
        !await confirm(context, 'Usarás datos móviles', 'La actualización ocupa ${update.sizeLabel}. ¿Descargarla ahora con datos móviles?', accept: 'Descargar')) {
      return;
    }
    _start();
  }

  void _start() {
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'Descargando…';
    });
    _subscription = AppUpdates.install(widget.update).listen((event) {
      setState(() {
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            _progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
            _status = 'Descargando… ${event.value ?? 0} %';
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            _progress = 1;
            _status = 'Sigue las instrucciones de Android para instalar la actualización.';
            _running = false;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            _status = 'Hace falta permitir que MiRuta instale aplicaciones. Actívelo en la pantalla que abrió Android y vuelva a intentarlo.';
            _running = false;
          case OtaStatus.CHECKSUM_ERROR:
            _status = 'El archivo descargado está dañado. Vuelve a intentarlo.';
            _running = false;
          default:
            _status = 'No se pudo completar la actualización (${event.value ?? event.status.name}). Vuelve a intentarlo.';
            _running = false;
        }
      });
    }, onError: (_) => setState(() {
          _status = 'No se pudo descargar la actualización. Revisa tu conexión.';
          _running = false;
        }));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    return PopScope(
      canPop: !update.mandatory,
      child: Scaffold(
        appBar: AppBar(title: const Text('Actualización'), automaticallyImplyLeading: !update.mandatory),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Icon(Icons.system_update, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('MiRuta ${update.versionName}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          Text('Descarga: ${update.sizeLabel} · ${update.abi == 'armeabi-v7a' ? '32 bits' : update.abi == 'arm64-v8a' ? '64 bits' : 'universal'}', textAlign: TextAlign.center),
          if (_mobileWarning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Estás con datos móviles y pediste actualizar solo con Wi-Fi.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (update.mandatory) ...[
            const SizedBox(height: 12),
            const Text('Esta actualización es obligatoria: hay que instalarla para seguir usando la app.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ],
          if (update.notes != null && update.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Novedades', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(update.notes!),
          ],
          const SizedBox(height: 24),
          if (_progress != null) LinearProgressIndicator(value: _progress),
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!, textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _confirmAndStart,
            icon: _running ? const BusyIndicator() : const Icon(Icons.download),
            label: Text(_mobileWarning ? 'Actualizar con datos móviles' : 'Actualizar'),
          ),
          if (!update.mandatory) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Más tarde')),
        ]),
      ),
    );
  }
}
