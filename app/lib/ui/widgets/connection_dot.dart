import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/connection.dart';
import '../../services/session.dart';
import '../../services/templates.dart';

/// Punto de conexión de la barra superior (docs/11 §11.14): verde si hay
/// conexión con el servidor y rojo si no; solo con la sesión iniciada. Al
/// tocarlo: «Conectado a …» o «Sin conexión con el servidor desde las hh:mm».
class ConnectionDot extends StatelessWidget {
  static const green = Color(0xFF2E7D32);
  static const red = Color(0xFFD32F2F);

  const ConnectionDot({super.key});

  @override
  Widget build(BuildContext context) {
    final ConnectionMonitor monitor;
    try {
      monitor = Provider.of<ConnectionMonitor>(context);
      if (Provider.of<Session>(context).state != SessionState.ready) return const SizedBox.shrink();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final online = monitor.online ?? true;
    final text = online
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
          color: online ? green : red,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }
}
