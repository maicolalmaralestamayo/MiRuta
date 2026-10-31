import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../theme.dart';

extension SessionContext on BuildContext {
  Session get session => read<Session>();

  ApiClient get api => read<Session>().api;

  Me get me => read<Session>().me!;

  /// filter[entity] de la Entidad elegida por el Administrador (nada para los demás:
  /// el servidor ya les muestra solo la suya).
  Map<String, dynamic> get entityFilter {
    final entity = read<Session>().adminEntity;
    return entity == null ? const {} : {'filter[entity]': entity.id};
  }

  /// Relación "entity" para crear algo como Administrador. Si no eligió una
  /// Entidad, avisa y devuelve null.
  Map<String, ResourceId?>? entityRelationship() {
    final session = read<Session>();
    if (!session.me!.isAdmin) return const {};
    final entity = session.adminEntity;
    if (entity == null) {
      showMessage(this, 'Elige primero una Entidad en Gestión.');
      return null;
    }
    return {'entity': ResourceId('entities', entity.id)};
  }
}

/// Muestra el error en una barra inferior.
void showError(BuildContext context, Object error) {
  final message = error is ApiException ? error.message : 'Ocurrió un error inesperado.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

Future<bool> confirm(BuildContext context, String title, String message, {String accept = 'Aceptar', bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(accept),
        ),
      ],
    ),
  );
  return result == true;
}

/// Pide un texto en un diálogo.
Future<String?> promptText(BuildContext context, String title, {String label = '', String initial = '', bool required = false, int maxLines = 1}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, decoration: InputDecoration(labelText: label), maxLines: maxLines, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (required && controller.text.trim().isEmpty) return;
            Navigator.pop(context, controller.text.trim());
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

/// Carga datos asíncronos con indicador, error con reintento y "tirar para actualizar".
class AsyncView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  const AsyncView({super.key, required this.load, required this.builder});

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> reload() async {
    final future = widget.load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return ErrorView(message: error is ApiException ? error.message : 'No se pudieron cargar los datos.', onRetry: reload);
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(onRefresh: reload, child: widget.builder(context, snapshot.data as T, reload));
      },
    );
  }
}

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

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyView({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    // ListView para que funcione "tirar para actualizar" aunque esté vacía.
    return ListView(children: [
      const SizedBox(height: 120),
      Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
    ]);
  }
}

class WorkerAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final double radius;

  WorkerAvatar(Worker worker, {super.key, this.radius = 20})
      : photoUrl = worker.photoUrl,
        initials = worker.initials;

  WorkerAvatar.of({super.key, required this.photoUrl, required PersonName name, this.radius = 20}) : initials = name.initials;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundImage: photo == null ? null : NetworkImage(photo),
      child: photo == null ? (initials.isEmpty ? const Icon(Icons.person) : Text(initials)) : null,
    );
  }
}

/// Icono de la jerarquía (o uno por defecto).
class RankBadge extends StatelessWidget {
  final Rank? rank;

  const RankBadge(this.rank, {super.key});

  @override
  Widget build(BuildContext context) {
    if (rank == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      rank!.iconUrl == null
          ? const Icon(Icons.military_tech_outlined, size: 16)
          : Image.network(rank!.iconUrl!, width: 16, height: 16, errorBuilder: (_, _, _) => const Icon(Icons.military_tech_outlined, size: 16)),
      const SizedBox(width: 4),
      Text(rank!.name, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const StatusChip(this.label, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Color tripStatusColor(String status) => const {
      TripStatus.unconfirmed: Colors.orange,
      TripStatus.confirmed: Colors.green,
      TripStatus.completed: Colors.blueGrey,
      TripStatus.cancelled: overloadColor,
    }[status] ?? Colors.grey;

/// Color de cada nivel de ocupación (docs/08-version-2.md §8.9).
Color? occupancyColor(String level) => const {'saturated': saturatedColor, 'overloaded': overloadColor}[level];

String occupancyLabel(String level) => const {'saturated': 'Saturado', 'overloaded': 'Sobresaturado'}[level] ?? 'Normal';

/// "35 trabajadores (+10 niños) · capacidad 40". Los niños van cargados:
/// no cuentan para la ocupación, pero se informan.
String occupancyText(int workers, int children, int capacity) =>
    '$workers trabajadores${children > 0 ? ' (+$children niños)' : ''} · capacidad $capacity';

/// Aviso llamativo de saturación (naranja: van de pie) o sobresaturación (rojo: no caben).
class OverloadBanner extends StatelessWidget {
  final String level;
  final int expected;
  final int children;
  final int seats;
  final int capacity;

  const OverloadBanner({super.key, required this.level, required this.expected, this.children = 0, required this.seats, required this.capacity});

  @override
  Widget build(BuildContext context) {
    final overloaded = level == 'overloaded';
    final color = occupancyColor(level) ?? overloadColor;
    final text = overloaded
        ? 'Transporte sobresaturado: ${expected - capacity} trabajadores no caben (${occupancyText(expected, children, capacity)}).'
        : 'Transporte saturado: ${expected - seats} trabajadores irán de pie (${occupancyText(expected, children, capacity)}, $seats asientos).';
    final foreground = overloaded ? Colors.white : Colors.black;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: foreground),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: foreground, fontWeight: FontWeight.bold))),
      ]),
    );
  }
}

/// Botón que, mientras espera al servidor, muestra el indicador de carga
/// dentro de él y queda desactivado (docs/08-version-2.md §8.12). Si la
/// acción falla, muestra el error (salvo que [showErrors] sea false).
class BusyButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final Widget? icon;
  final BusyButtonStyle style;
  final bool showErrors;
  final ButtonStyle? buttonStyle;

  const BusyButton({super.key, required this.onPressed, required this.child, this.icon, this.style = BusyButtonStyle.filled, this.showErrors = true, this.buttonStyle});

  const BusyButton.tonal({super.key, required this.onPressed, required this.child, this.icon, this.showErrors = true, this.buttonStyle})
      : style = BusyButtonStyle.tonal;

  const BusyButton.text({super.key, required this.onPressed, required this.child, this.icon, this.showErrors = true, this.buttonStyle})
      : style = BusyButtonStyle.text;

  const BusyButton.outlined({super.key, required this.onPressed, required this.child, this.icon, this.showErrors = true, this.buttonStyle})
      : style = BusyButtonStyle.outlined;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

enum BusyButtonStyle { filled, tonal, text, outlined }

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (error) {
      // Con showErrors = false, la propia acción muestra sus errores.
      if (widget.showErrors && mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final child = _busy ? const BusyIndicator() : widget.child;
    final icon = _busy ? null : widget.icon;
    switch (widget.style) {
      case BusyButtonStyle.filled:
        return icon == null
            ? FilledButton(style: widget.buttonStyle, onPressed: onPressed, child: child)
            : FilledButton.icon(style: widget.buttonStyle, onPressed: onPressed, icon: icon, label: child);
      case BusyButtonStyle.tonal:
        return icon == null
            ? FilledButton.tonal(style: widget.buttonStyle, onPressed: onPressed, child: child)
            : FilledButton.tonalIcon(style: widget.buttonStyle, onPressed: onPressed, icon: icon, label: child);
      case BusyButtonStyle.text:
        return icon == null
            ? TextButton(style: widget.buttonStyle, onPressed: onPressed, child: child)
            : TextButton.icon(style: widget.buttonStyle, onPressed: onPressed, icon: icon, label: child);
      case BusyButtonStyle.outlined:
        return icon == null
            ? OutlinedButton(style: widget.buttonStyle, onPressed: onPressed, child: child)
            : OutlinedButton.icon(style: widget.buttonStyle, onPressed: onPressed, icon: icon, label: child);
    }
  }
}

/// Icono de acción con indicador de carga en su lugar mientras espera.
class BusyIconButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget icon;
  final String? tooltip;

  const BusyIconButton({super.key, required this.onPressed, required this.icon, this.tooltip});

  @override
  State<BusyIconButton> createState() => _BusyIconButtonState();
}

class _BusyIconButtonState extends State<BusyIconButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      icon: _busy ? const BusyIndicator() : widget.icon,
      onPressed: widget.onPressed == null || _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onPressed!();
              } catch (error) {
                if (context.mounted) showError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}

/// Elemento de lista que lanza una acción: el indicador de carga sustituye
/// al icono final mientras espera.
class BusyListTile extends StatefulWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final Future<void> Function()? onTap;

  const BusyListTile({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  State<BusyListTile> createState() => _BusyListTileState();
}

class _BusyListTileState extends State<BusyListTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: _busy ? const BusyIndicator() : widget.trailing,
      enabled: widget.onTap != null,
      onTap: widget.onTap == null || _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onTap!();
              } catch (error) {
                if (context.mounted) showError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}

/// Interruptor que muestra el indicador de carga mientras guarda.
class BusySwitchListTile extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final Future<void> Function(bool value)? onChanged;

  const BusySwitchListTile({super.key, required this.title, this.subtitle, required this.value, this.onChanged});

  @override
  State<BusySwitchListTile> createState() => _BusySwitchListTileState();
}

class _BusySwitchListTileState extends State<BusySwitchListTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return ListTile(title: widget.title, subtitle: widget.subtitle, trailing: const BusyIndicator());
    }
    return SwitchListTile(
      title: widget.title,
      subtitle: widget.subtitle,
      value: widget.value,
      onChanged: widget.onChanged == null
          ? null
          : (value) async {
              setState(() => _busy = true);
              try {
                await widget.onChanged!(value);
              } catch (error) {
                if (context.mounted) showError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}

/// Indicador de carga pequeño, para dentro de botones y controles.
class BusyIndicator extends StatelessWidget {
  final double size;

  const BusyIndicator({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size, child: const CircularProgressIndicator(strokeWidth: 2));
}

class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Selector de un elemento de una lista cargada de la API.
Future<T?> pickFrom<T>(BuildContext context, String title, List<T> items, String Function(T) label, {String Function(T)? subtitle}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final item in items)
                ListTile(
                  title: Text(label(item)),
                  subtitle: subtitle == null ? null : Text(subtitle(item)),
                  onTap: () => Navigator.pop(context, item),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
