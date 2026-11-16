import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../theme.dart';
import 'busy.dart';

const red = Color(0xFFD32F2F);
const green = Color(0xFF2E7D32);
const grey = Color(0xFF767680);
const blue2 = Color(0xFF1565C0);
const purple = Color(0xFF6A1B9A);
const amber = Color(0xFFE65100);

/// Color de estado legible también en el tema oscuro (más claro sobre fondo oscuro).
Color readable(BuildContext context, Color color) =>
    Theme.of(context).brightness == Brightness.dark ? Color.lerp(color, Colors.white, 0.45)! : color;

extension SessionContext on BuildContext {
  Session get session => read<Session>();

  ApiClient get api => read<Session>().api;

  Me get me => read<Session>().me!;
}

/// Diálogo «Falta el servidor» (docs/11 §11.50): cada vez que se intenta
/// operar la app sin servidor indicado. Devuelve true si eligió «Indicar servidor».
Future<bool> showMissingServer(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      icon: const Icon(Icons.dns_outlined, size: 32, color: red),
      title: 'Falta el servidor',
      content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Para usar la app indique primero la dirección del servidor.'),
        SizedBox(height: 8),
        Text('Pulse el botón rojo «Servidor», arriba.'),
      ]),
      buttons: [
        primaryButton(context, 'Indicar servidor', Icons.dns_outlined, () => Navigator.pop(context, true)),
        cancelButton(context),
      ],
    ),
  );
  return result == true;
}

/// Muestra el error en una barra inferior (sin servidor: el diálogo).
void showError(BuildContext context, Object error) {
  if (error is ApiException && error.code == 'NO_SERVER') {
    showMissingServer(context);
    return;
  }
  if (error is ApiException && error.isCancelled) {
    showResult(ScaffoldMessenger.of(context), 'Operación cancelada', cancelled: true);
    return;
  }
  // Sin conexión solo se consulta lo guardado (docs/11 §11.62); salvo «Incluir por QR».
  final message = error is ApiException && error.isNetwork
      ? 'Sin conexión: solo se puede consultar lo guardado en el teléfono. Los cambios necesitan el servidor.'
      : error is ApiException
          ? error.message
          : (error is StateError ? error.message : 'Ocurrió un error inesperado.');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Ejecuta una operación del usuario con el spinner «[Acción] [Objeto]»
/// ([label], p. ej. «Creando Parada») y «✕ Cancelar» (docs/11 §11.65); al
/// final, nada (sin cintas) o el error. Devuelve true si salió bien.
Future<bool> runAction(BuildContext context, FutureOr<void> Function() action, {String? success, String? label}) =>
    runBusy(context, action, done: success, label: label, onError: showError);

/// Modal de la app (docs/11 §11.65, puntos 6 a 8): ícono, título, contenido y
/// los botones a todo el ancho, uno debajo del otro, la acción arriba y
/// Cancelar abajo.
class AppDialog extends StatelessWidget {
  final Widget? icon;
  final String? title;
  final Widget? content;
  final List<Widget> buttons;

  /// Contenido sin márgenes laterales (listas).
  final bool flush;

  const AppDialog({super.key, this.icon, this.title, this.content, this.buttons = const [], this.flush = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (icon != null) Center(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: icon!)),
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(title!, textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
              ),
            if (content != null)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(flush ? 0 : 24, 12, flush ? 0 : 24, 4),
                  child: flush ? content! : SingleChildScrollView(child: content!),
                ),
              ),
            if (buttons.isNotEmpty) const SizedBox(height: 12),
            for (final b in buttons) Padding(padding: const EdgeInsets.fromLTRB(24, 4, 24, 4), child: SizedBox(width: double.infinity, height: 48, child: b)),
          ]),
        ),
      ),
    );
  }
}

/// Botón de la acción de un modal, en el color principal (Confirmar, Guardar…).
Widget primaryButton(BuildContext context, String label, IconData icon, VoidCallback? onPressed) =>
    FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));

/// Botón Eliminar (o de una acción destructiva) de un modal: siempre en rojo.
Widget dangerButton(BuildContext context, String label, IconData icon, VoidCallback? onPressed) => FilledButton.icon(
    style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white), onPressed: onPressed, icon: Icon(icon), label: Text(label));

/// Otra opción de un modal (ni la principal ni Cancelar).
Widget otherButton(BuildContext context, String label, IconData icon, VoidCallback? onPressed) =>
    OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));

/// Botón Cancelar de un modal: siempre en gris y abajo (docs/11 §11.65).
Widget cancelButton(BuildContext context, {String label = 'Cancelar', IconData icon = Icons.close}) => FilledButton.icon(
    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE0E0E0), foregroundColor: const Color(0xFF424242)),
    onPressed: () => Navigator.pop(context),
    icon: Icon(icon),
    label: Text(label));

/// Modal simple (docs/11 §11.56 y §11.65): ícono, título, pregunta y los
/// botones uno debajo del otro: la acción (color principal, o rojo si
/// [destructive]) y Cancelar (gris). [cancel] es el texto del botón que
/// vuelve sin hacer nada (p. ej. «Volver» cuando la acción es «Cancelar solicitud»).
Future<bool> confirm(BuildContext context, String title, String message,
    {String accept = 'Confirmar', IconData icon = Icons.check, bool destructive = false, IconData? headerIcon, String cancel = 'Cancelar', IconData cancelIcon = Icons.close}) async {
  final color = destructive ? red : Theme.of(context).colorScheme.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      icon: Icon(headerIcon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline), color: color, size: 32),
      title: title,
      content: Text(message, textAlign: TextAlign.center),
      buttons: [
        destructive
            ? dangerButton(context, accept, icon, () => Navigator.pop(context, true))
            : primaryButton(context, accept, icon, () => Navigator.pop(context, true)),
        cancelButton(context, label: cancel, icon: cancelIcon),
      ],
    ),
  );
  return result == true;
}

/// Confirmación de eliminar, explicando qué se borra y qué se conserva.
Future<bool> confirmDelete(BuildContext context, String what, {String? consequences}) =>
    confirm(context, 'Eliminar', '¿Eliminar $what?${consequences == null ? '' : '\n\n$consequences'}',
        accept: 'Eliminar', icon: Icons.delete_outline, destructive: true, headerIcon: Icons.delete_outline);

enum LeaveChoice { save, leave, cancel }

/// «Salir sin guardar» (docs/11 §11.65, punto 8): el mismo en todos los
/// formularios. Botones: Guardar (color principal, si se puede guardar),
/// Salir sin guardar (rojo) y Cancelar (gris).
Future<LeaveChoice> confirmLeave(BuildContext context, {bool canSave = true}) async {
  final result = await showDialog<LeaveChoice>(
    context: context,
    builder: (context) => AppDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: red, size: 32),
      title: 'Salir sin guardar',
      content: const Text('Hay cambios sin guardar. ¿Qué desea hacer?', textAlign: TextAlign.center),
      buttons: [
        if (canSave) primaryButton(context, 'Guardar', Icons.save_outlined, () => Navigator.pop(context, LeaveChoice.save)),
        dangerButton(context, 'Salir sin guardar', Icons.logout, () => Navigator.pop(context, LeaveChoice.leave)),
        cancelButton(context),
      ],
    ),
  );
  return result ?? LeaveChoice.cancel;
}

/// Protege un formulario: si hay cambios sin guardar ([dirty]), al salir
/// pregunta «Salir sin guardar» (Guardar / Salir sin guardar / Cancelar).
/// [onSave] guarda (con su spinner) y devuelve true si salió bien.
class LeaveGuard extends StatelessWidget {
  final bool Function() dirty;
  final Future<bool> Function()? onSave;
  final Widget child;

  const LeaveGuard({super.key, required this.dirty, this.onSave, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!dirty()) {
          if (navigator.mounted) navigator.pop(result);
          return;
        }
        final choice = await confirmLeave(navigator.context, canSave: onSave != null);
        switch (choice) {
          case LeaveChoice.leave:
            if (navigator.mounted) navigator.pop(result);
          case LeaveChoice.save:
            if (await onSave!() && navigator.mounted && navigator.canPop()) navigator.pop(true);
          case LeaveChoice.cancel:
            break;
        }
      },
      child: child,
    );
  }
}

/// Pide un texto en un diálogo.
Future<String?> promptText(BuildContext context, String title,
    {String label = '', String initial = '', bool required = false, int maxLines = 1, String accept = 'Aceptar', IconData icon = Icons.check, TextInputType? keyboard, IconData headerIcon = Icons.edit_note}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AppDialog(
      icon: Icon(headerIcon, size: 32),
      title: title,
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLines: maxLines,
        autofocus: true,
        keyboardType: keyboard,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (required && controller.text.trim().isEmpty) return;
          Navigator.pop(context, controller.text.trim());
        },
      ),
      buttons: [
        primaryButton(context, accept, icon, () {
          if (required && controller.text.trim().isEmpty) return;
          Navigator.pop(context, controller.text.trim());
        }),
        cancelButton(context),
      ],
    ),
  );
}

/// Elegir una opción de una lista (diálogo con búsqueda opcional).
Future<T?> pickOne<T>(BuildContext context, String title, List<T> items, String Function(T) label,
    {String Function(T)? subtitle, IconData icon = Icons.chevron_right, bool search = false, T? selected}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      var filter = '';
      return StatefulBuilder(builder: (context, setState) {
        final visible = items.where((i) => filter.isEmpty || '${label(i)} ${subtitle?.call(i) ?? ''}'.toLowerCase().contains(filter.toLowerCase())).toList();
        return AppDialog(
          title: title,
          flush: true,
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (search)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar'), onChanged: (v) => setState(() => filter = v)),
                ),
              Flexible(
                child: visible.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('No hay opciones.'))
                    : ListView(shrinkWrap: true, children: [
                        for (final item in visible)
                          ListTile(
                            title: Text(label(item)),
                            subtitle: subtitle == null ? null : Text(subtitle(item)),
                            trailing: item == selected ? const Icon(Icons.check, color: orange) : null,
                            onTap: () => Navigator.pop(context, item),
                          ),
                      ]),
              ),
            ]),
          ),
          buttons: [cancelButton(context)],
        );
      });
    },
  );
}

/// Indicador de carga pequeño (botones).
class BusyIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const BusyIndicator({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CircularProgressIndicator(strokeWidth: 2.5, color: color));
}

/// Botón con ícono y texto que muestra el indicador mientras espera.
class BusyButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  final IconData icon;
  final String label;
  final ButtonStyle? style;
  final bool outlined;
  final double height;

  const BusyButton({super.key, required this.onPressed, required this.icon, required this.label, this.style, this.outlined = false, this.height = 52});

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await runAction(context, widget.onPressed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy ? const BusyIndicator() : Icon(widget.icon);
    final label = Text(widget.label, style: const TextStyle(fontSize: 16));
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: widget.outlined
          ? OutlinedButton.icon(onPressed: _busy ? null : _run, style: widget.style, icon: icon, label: label)
          : FilledButton.icon(onPressed: _busy ? null : _run, style: widget.style, icon: icon, label: label),
    );
  }
}

/// Error con reintento.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

String errorText(Object? error) => error is ApiException ? error.message : 'No se pudieron cargar los datos.';

/// Campo de texto del estilo de las maquetas (etiqueta arriba, candado si es de solo lectura).
class FormText extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? value;
  final bool readOnly;
  final IconData? icon;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final VoidCallback? onTap;
  final bool enabled;
  final TextCapitalization capitalization;

  /// Último campo del formulario: el teclado muestra «Listo» en vez de
  /// «Siguiente» (docs/11 §11.56: se recorre todo con el teclado).
  final bool last;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const FormText({
    super.key,
    this.controller,
    required this.label,
    this.value,
    this.readOnly = false,
    this.icon,
    this.hint,
    this.validator,
    this.keyboard,
    this.formatters,
    this.maxLines = 1,
    this.onTap,
    this.enabled = true,
    this.capitalization = TextCapitalization.sentences,
    this.last = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? (value ?? '') : null,
        readOnly: readOnly || onTap != null || !enabled,
        onTap: onTap,
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLines: maxLines,
        textCapitalization: capitalization,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        focusNode: focusNode,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        // Los de solo lectura no reciben el foco del teclado.
        canRequestFocus: !(readOnly || !enabled) || onTap != null,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: readOnly || !enabled ? const Icon(Icons.lock_outline, size: 18) : null,
        ),
      ),
    );
  }
}

/// Interruptor «Activado» de los formularios (docs/11 §11.26).
class ActiveSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  const ActiveSwitch({super.key, required this.value, this.onChanged, this.label = 'Activado'});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: SwitchListTile(value: value, onChanged: onChanged, title: Text(label), contentPadding: EdgeInsets.zero),
      );
}

String? requiredText(String? value, String message) => (value ?? '').trim().isEmpty ? message : null;
