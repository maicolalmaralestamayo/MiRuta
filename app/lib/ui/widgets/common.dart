import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/session.dart';
import '../theme.dart';

extension SessionContext on BuildContext {
  Session get session => read<Session>();

  ApiClient get api => read<Session>().api;

  Worker get me => read<Session>().me!;
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
  final Worker worker;
  final double radius;

  const WorkerAvatar(this.worker, {super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final photo = worker.photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundImage: photo == null ? null : NetworkImage(photo),
      child: photo == null ? (worker.initials.isEmpty ? const Icon(Icons.person) : Text(worker.initials)) : null,
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

/// Aviso llamativo de sobresaturación.
class OverloadBanner extends StatelessWidget {
  final int expected;
  final int capacity;

  const OverloadBanner({super.key, required this.expected, required this.capacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: overloadColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Transporte sobresaturado: $expected pasajeros esperados para $capacity plazas.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
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
