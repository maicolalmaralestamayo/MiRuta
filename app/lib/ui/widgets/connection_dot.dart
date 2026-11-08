import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../services/connection.dart';

/// Punto de conexión de la barra superior (docs/11 §11.14 y §11.50): verde
/// con conexión al servidor, rojo sin ella y gris si aún no hay servidor. Al
/// tocarlo: «Conectado a …» o «Sin conexión con el servidor desde las hh:mm».
class ConnectionDot extends StatelessWidget {
  static const green = Color(0xFF2E7D32);
  static const red = Color(0xFFD32F2F);
  static const grey = Color(0xFF9E9E9E);

  /// Borde blanco (sobre la barra azul) o sin borde (pantalla de inicio de sesión).
  final bool onBar;

  const ConnectionDot({super.key, this.onBar = true});

  @override
  Widget build(BuildContext context) {
    final ConnectionMonitor monitor;
    try {
      monitor = Provider.of<ConnectionMonitor>(context);
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final hasServer = monitor.api.hasServer;
    final online = monitor.online ?? hasServer;
    final text = !hasServer
        ? 'Aún no ha indicado el servidor'
        : online
            ? 'Conectado a ${monitor.server}'
            : 'Sin conexión con el servidor desde las ${formatTime(monitor.offlineSince ?? DateTime.now())}';
    return IconButton(
      tooltip: text,
      onPressed: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
        monitor.check();
      },
      icon: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: !hasServer ? grey : (online ? green : red),
          shape: BoxShape.circle,
          border: onBar ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
      ),
    );
  }
}
