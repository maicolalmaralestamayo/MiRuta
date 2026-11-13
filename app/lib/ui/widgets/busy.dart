import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/busy_scope.dart';
import '../theme.dart';

/// Operación del usuario contra el servidor (docs/11 §11.56, maqueta G19
/// n.º 7 y 8): mientras se conecta, un spinner que bloquea la app con
/// «Cancelar»; al terminar, un mensaje muy escueto: el resultado ([done],
/// p. ej. «Itinerario creado») o «Operación cancelada». Los errores se
/// muestran con [onError]. Devuelve true si terminó bien.
///
/// El spinner solo se ve mientras hay peticiones en curso: los diálogos de
/// la propia operación (elegir, confirmar) se usan con normalidad.
Future<bool> runBusy(BuildContext context, FutureOr<void> Function() action,
    {String? done, required void Function(BuildContext context, Object error) onError}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  Route<void>? route;
  Timer? hide;

  void close() {
    hide?.cancel();
    final r = route;
    route = null;
    if (r != null && r.isActive) navigator.removeRoute(r);
  }

  void changed(BusyScope scope) {
    if (scope.busy && !scope.cancelled) {
      hide?.cancel();
      if (route == null && navigator.mounted) {
        route = DialogRoute<void>(
          context: navigator.context,
          barrierDismissible: false,
          barrierColor: Colors.black54,
          builder: (_) => PopScope(canPop: false, child: BusyDialog(onCancel: scope.cancel)),
        );
        navigator.push(route!);
      }
    } else {
      // Peticiones seguidas: sin parpadeo.
      hide?.cancel();
      hide = scope.cancelled ? null : Timer(const Duration(milliseconds: 120), close);
      if (scope.cancelled) close();
    }
  }

  final scope = BusyScope(onBusyChanged: changed);
  try {
    await scope.run(() async => await action());
    close();
    if (done != null && messenger != null) showResult(messenger, done);
    return true;
  } catch (error) {
    close();
    if (scope.cancelled || (error is ApiException && error.isCancelled)) {
      if (messenger != null) showResult(messenger, 'Operación cancelada', cancelled: true);
    } else if (context.mounted) {
      onError(context, error);
    }
    return false;
  } finally {
    scope.close();
    close();
  }
}

/// Mensaje escueto del resultado (con su ícono).
void showResult(ScaffoldMessengerState messenger, String text, {bool cancelled = false}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle, color: cancelled ? Colors.white70 : const Color(0xFF66BB6A)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
      duration: const Duration(seconds: 3),
    ));
}

/// «Conectando con el servidor…» con el botón «Cancelar».
class BusyDialog extends StatelessWidget {
  final VoidCallback onCancel;

  const BusyDialog({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3.5, color: orange)),
          const SizedBox(height: 20),
          Text('Conectando con el servidor…', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.close), label: const Text('Cancelar')),
        ]),
      ),
    );
  }
}
