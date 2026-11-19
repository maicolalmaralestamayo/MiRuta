import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/busy_scope.dart';
import '../theme.dart';

/// «Crear Parada» → «Creando Parada»; «Aprobar Solicitud» → «Aprobando
/// Solicitud»; «Cancelar Viaje» → «Cancelando Viaje» (docs/11 §11.65 y
/// §11.67: nombres propios de las acciones). Null si la acción no empieza por
/// un verbo conocido.
String? progressiveLabel(String? action) {
  if (action == null) return null;
  final text = action.split(':').first.trim();
  for (final (verb, ing) in _gerunds) {
    if (text == verb) return ing;
    if (text.startsWith('$verb ')) return '$ing ${text.substring(verb.length + 1)}';
  }
  return null;
}

const _gerunds = [
  ('Consultar', 'Consultando'),
  ('Crear', 'Creando'),
  ('Actualizar', 'Actualizando'),
  ('Eliminar', 'Eliminando'),
  ('Aprobar', 'Aprobando'),
  ('Rechazar', 'Rechazando'),
  ('Solicitar', 'Solicitando'),
  ('Cancelar', 'Cancelando'),
  ('Iniciar', 'Iniciando'),
  ('Terminar', 'Terminando'),
  ('Marcar', 'Marcando'),
  ('Asociar', 'Asociando'),
  ('Añadir', 'Añadiendo'),
  ('Quitar', 'Quitando'),
  ('Asignar', 'Asignando'),
  ('Cambiar', 'Cambiando'),
  ('Indicar', 'Indicando'),
  ('Incluir', 'Incluyendo'),
  ('Salir', 'Saliendo'),
  ('Guardar', 'Guardando'),
];

/// Lo que muestra el spinner de una operación en curso.
class BusyRequest {
  final String text;
  final VoidCallback onCancel;

  const BusyRequest(this.text, this.onCancel);
}

/// Spinner de las operaciones (docs/11 §11.65, punto 8): lo muestran las
/// pantallas con sesión (AppScaffold) sobre su zona de trabajo, con la barra
/// superior y la de navegación visibles.
class BusyOverlay {
  static final current = ValueNotifier<BusyRequest?>(null);

  /// Pantallas con zona de trabajo montadas (sin ninguna, el spinner va en un diálogo).
  static int hosts = 0;
}

/// Spinner sobre fondo blanco: «[Acción] [Objeto]», el círculo girando en el
/// color de acento (naranja) y «✕ Cancelar» gris debajo (docs/11 §11.65).
/// No deja ver formularios ni interfaces.
class BusyPanel extends StatelessWidget {
  final String text;
  final VoidCallback? onCancel;

  const BusyPanel({super.key, required this.text, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ColoredBox(
      color: t.colorScheme.surface,
      child: SizedBox.expand(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, textAlign: TextAlign.center, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 4, color: orange)),
              if (onCancel != null) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: greyButton),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Gris de los botones Cancelar (docs/11 §11.65, punto 7).
const greyButton = Color(0xFF757575);

/// Operación del usuario contra el servidor (docs/11 §11.56 y §11.65): mientras
/// se conecta, el spinner «[Acción] [Objeto]» ([label], p. ej. «Creando
/// Parada») sobre la zona de trabajo, con «✕ Cancelar». Ya no hay mensaje al
/// terminar (se quitaron las cintas de abajo). Los errores se muestran con
/// [onError]. Devuelve true si terminó bien.
///
/// El spinner solo se ve mientras hay peticiones en curso: los diálogos de
/// la propia operación (elegir, confirmar) se usan con normalidad.
Future<bool> runBusy(BuildContext context, FutureOr<void> Function() action,
    {String? done, String? label, required void Function(BuildContext context, Object error) onError}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final text = label ?? 'Conectando con el servidor';
  Route<void>? route;
  BusyRequest? request;
  Timer? hide;

  void close() {
    hide?.cancel();
    final r = route;
    route = null;
    if (r != null && r.isActive) navigator.removeRoute(r);
    if (request != null && BusyOverlay.current.value == request) BusyOverlay.current.value = null;
    request = null;
  }

  void changed(BusyScope scope) {
    if (scope.busy && !scope.cancelled) {
      hide?.cancel();
      if (route != null || request != null) return;
      if (BusyOverlay.hosts > 0) {
        request = BusyRequest(scope.label ?? text, scope.cancel);
        BusyOverlay.current.value = request;
      } else if (navigator.mounted) {
        route = DialogRoute<void>(
          context: navigator.context,
          barrierDismissible: false,
          barrierColor: Colors.black54,
          builder: (_) => PopScope(canPop: false, child: BusyDialog(text: scope.label ?? text, onCancel: scope.cancel)),
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
    return true;
  } catch (error) {
    close();
    if (!scope.cancelled && !(error is ApiException && error.isCancelled) && context.mounted) onError(context, error);
    return false;
  } finally {
    scope.close();
    close();
  }
}

/// Antes, el mensaje escueto del resultado; desde la 4.4.0 no se muestra
/// nada al terminar una acción (docs/11 §11.65, punto 10).
void showResult(ScaffoldMessengerState messenger, String text, {bool cancelled = false}) {}

/// El spinner en un diálogo (pantallas sin barra de navegación, como el inicio de sesión).
class BusyDialog extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;

  const BusyDialog({super.key, this.text = 'Conectando con el servidor', required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(height: 220, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: BusyPanel(text: text, onCancel: onCancel))),
    );
  }
}
