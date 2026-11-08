import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../theme.dart';

const red = Color(0xFFD32F2F);
const green = Color(0xFF2E7D32);
const grey = Color(0xFF767680);
const blue2 = Color(0xFF1565C0);
const purple = Color(0xFF6A1B9A);
const amber = Color(0xFFE65100);

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
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.dns_outlined, size: 32, color: red),
      title: const Text('Falta el servidor'),
      content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Para usar la app indique primero la dirección del servidor.'),
        SizedBox(height: 8),
        Text('Pulse el botón rojo «Servidor», arriba.'),
      ]),
      actions: [
        TextButton.icon(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close), label: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: red),
          icon: const Icon(Icons.dns_outlined),
          label: const Text('Indicar servidor'),
        ),
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
  final message = error is ApiException ? error.message : (error is StateError ? error.message : 'Ocurrió un error inesperado.');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Ejecuta una acción mostrando el error si falla. Devuelve true si salió bien.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

/// Botones de los diálogos: «Cancelar» también con ícono (docs/11 §11.52).
Widget cancelButton(BuildContext context) =>
    TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('Cancelar'));

Future<bool> confirm(BuildContext context, String title, String message, {String accept = 'Aceptar', IconData icon = Icons.check, bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        cancelButton(context),
        FilledButton.icon(
          style: destructive ? FilledButton.styleFrom(backgroundColor: red) : null,
          onPressed: () => Navigator.pop(context, true),
          icon: Icon(icon),
          label: Text(accept),
        ),
      ],
    ),
  );
  return result == true;
}

/// Confirmación de eliminar, explicando qué se borra y qué se conserva.
Future<bool> confirmDelete(BuildContext context, String what, {String? consequences}) =>
    confirm(context, 'Eliminar', '¿Eliminar $what?${consequences == null ? '' : '\n\n$consequences'}', accept: 'Eliminar', icon: Icons.delete_outline, destructive: true);

/// Pide un texto en un diálogo.
Future<String?> promptText(BuildContext context, String title,
    {String label = '', String initial = '', bool required = false, int maxLines = 1, String accept = 'Aceptar', IconData icon = Icons.check, TextInputType? keyboard}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, decoration: InputDecoration(labelText: label), maxLines: maxLines, autofocus: true, keyboardType: keyboard),
      actions: [
        cancelButton(context),
        FilledButton.icon(
          onPressed: () {
            if (required && controller.text.trim().isEmpty) return;
            Navigator.pop(context, controller.text.trim());
          },
          icon: Icon(icon),
          label: Text(accept),
        ),
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
        return AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
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
          actions: [cancelButton(context)],
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
      await widget.onPressed();
    } catch (error) {
      if (mounted) showError(context, error);
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
