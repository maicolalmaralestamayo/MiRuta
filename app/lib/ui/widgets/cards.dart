import 'package:flutter/material.dart';

import '../../core/storage.dart';
import 'common.dart';

/// Imagen de una tarjeta: foto (si hay) o ícono sobre fondo claro.
class CardImage extends StatelessWidget {
  final String? url;
  final ImageProvider? image;
  final IconData icon;
  final bool round;
  final double size;
  final bool dim;

  const CardImage({super.key, this.url, this.image, required this.icon, this.round = false, this.size = 56, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = image ?? (url == null || url!.isEmpty ? null : NetworkImage(url!));
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(round ? size : 10),
        child: Container(
          width: size,
          height: size,
          color: scheme.primaryContainer,
          child: provider != null
              ? Image(image: provider, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(icon, size: size * 0.55, color: scheme.primary))
              : Icon(icon, size: size * 0.55, color: scheme.primary),
        ),
      ),
    );
  }
}

/// Etiqueta de estado («Planificado», «Pendiente», «Mi parada»…).
class Chip2 extends StatelessWidget {
  final String text;
  final Color color;

  const Chip2(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Tarjeta modelo (docs/11 §11.23): sin botones dentro; tocar = abrir;
/// mantener = marcar (check naranja arriba a la derecha).
class InfoCard extends StatelessWidget {
  final List<Widget> images;
  final String title;
  final List<String> lines;
  final Widget? chip;
  final Widget? trailing;
  final bool dim;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets margin;

  const InfoCard({
    super.key,
    required this.images,
    required this.title,
    this.lines = const [],
    this.chip,
    this.trailing,
    this.dim = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant.withValues(alpha: dim ? 0.6 : 1));
    Widget line(String text, TextStyle style) => Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    final card = Card(
      margin: margin,
      color: selected ? t.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? t.colorScheme.primary : t.colorScheme.outline, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            for (var i = 0; i < images.length; i++) ...[if (i > 0) const SizedBox(width: 6), images[i]],
            if (images.isNotEmpty) const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: line(title, t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: dim ? t.disabledColor : null))),
                  if (chip != null) ...[const SizedBox(width: 6), chip!],
                ]),
                const SizedBox(height: 2),
                for (final l in lines) line(l, muted),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
    if (!selected) return card;
    return Stack(clipBehavior: Clip.none, children: [
      card,
      Positioned(
        right: 4,
        top: -2,
        child: Container(
          decoration: BoxDecoration(color: t.colorScheme.secondary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: const Icon(Icons.check, size: 20, color: Colors.black),
        ),
      ),
    ]);
  }
}

/// Título de un grupo (sin plegar).
class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

Widget separator() => const Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 0), child: Divider(thickness: 2, height: 2));

/// Selector (docs/11 §11.23): tarjeta con ↕ que solo despliega su lista.
class SelectorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback? onTap;
  final bool enabled;

  const SelectorCard({super.key, required this.icon, required this.title, this.lines = const [], this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InfoCard(
      images: [CardImage(icon: icon)],
      title: title,
      lines: lines,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onTap : null,
      trailing: enabled
          ? Container(
              decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.unfold_more, color: t.colorScheme.onSecondaryContainer),
            )
          : null,
    );
  }
}

/// Botón grande de Inicio (Perfil, Hijos, Mi QR).
class QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickButton(this.icon, this.label, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: t.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 72,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 26, color: t.colorScheme.onSecondaryContainer),
                const SizedBox(height: 4),
                Text(label, style: t.textTheme.labelLarge!.copyWith(color: t.colorScheme.onSecondaryContainer)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso de lo que falta («Aún no tiene Entidad») con su botón.
class NoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final IconData? buttonIcon;
  final String? buttonText;
  final VoidCallback? onPressed;
  final Color color;

  const NoticeCard({super.key, required this.icon, required this.title, required this.detail, this.buttonIcon, this.buttonText, this.onPressed, this.color = amber});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(side: BorderSide(color: color.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text(detail, style: t.textTheme.bodyMedium),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: onPressed, icon: Icon(buttonIcon ?? Icons.arrow_forward), label: Text(buttonText!))),
          ],
        ]),
      ),
    );
  }
}

/// Foto o imagen del formulario con el botón de la cámara.
class PhotoHeader extends StatelessWidget {
  final String? url;
  final IconData icon;
  final VoidCallback? onTap;

  const PhotoHeader({super.key, this.url, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Stack(children: [
            CardImage(url: url, icon: icon, round: true, size: 104),
            if (onTap != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 18, backgroundColor: t.colorScheme.secondary, child: const Icon(Icons.photo_camera, size: 18, color: Colors.black)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Sección plegable con su cantidad que recuerda si estaba plegada
/// (docs/11 §11.26), paginada de 5 en 5 (salvo [paginate] false).
class FoldSection<T> extends StatefulWidget {
  /// Clave para recordar si estaba plegada (p. ej. «gestion.personas»).
  final String storageKey;
  final String title;
  final List<T> items;
  final Widget Function(T item) builder;
  final bool paginate;
  final int pageSize;

  /// Cantidad total si no son todos los cargados.
  final int? total;
  final String? emptyText;
  final bool initiallyOpen;

  /// Contenido en lugar de las tarjetas (p. ej. una lista para arrastrar).
  final Widget? child;

  const FoldSection({
    super.key,
    required this.storageKey,
    required this.title,
    required this.items,
    required this.builder,
    this.paginate = true,
    this.pageSize = 5,
    this.total,
    this.emptyText,
    this.initiallyOpen = true,
    this.child,
  });

  @override
  State<FoldSection<T>> createState() => _FoldSectionState<T>();
}

class _FoldSectionState<T> extends State<FoldSection<T>> {
  static final Map<String, bool> _memory = {};
  late bool _open = _memory[widget.storageKey] ?? widget.initiallyOpen;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (!_memory.containsKey(widget.storageKey)) {
      Storage.getString('fold.${widget.storageKey}').then((value) {
        if (value != null && mounted) setState(() => _open = _memory[widget.storageKey] = value == '1');
      });
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    _memory[widget.storageKey] = _open;
    Storage.setString('fold.${widget.storageKey}', _open ? '1' : '0');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final count = widget.total ?? widget.items.length;
    final pages = widget.paginate ? ((widget.items.length + widget.pageSize - 1) ~/ widget.pageSize).clamp(1, 1 << 20) : 1;
    if (_page >= pages) _page = pages - 1;
    final visible = widget.paginate ? widget.items.skip(_page * widget.pageSize).take(widget.pageSize).toList() : widget.items;
    final children = <Widget>[
      InkWell(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
          child: Row(children: [
            Expanded(child: Text('${widget.title} ($count)', style: t.textTheme.titleSmall!.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700))),
            Icon(_open ? Icons.expand_less : Icons.expand_more, color: t.colorScheme.primary),
          ]),
        ),
      ),
    ];
    if (_open) {
      if (widget.child != null) {
        children.add(widget.child!);
      } else if (widget.items.isEmpty) {
        children.add(Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(widget.emptyText ?? 'No hay nada que mostrar.', style: t.textTheme.bodyMedium)));
      } else {
        children.addAll(visible.map(widget.builder));
        if (widget.paginate && widget.items.length > widget.pageSize) {
          final first = _page * widget.pageSize + 1;
          final last = (first + widget.pageSize - 1).clamp(1, widget.items.length);
          children.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: 'Primera página', onPressed: _page > 0 ? () => setState(() => _page = 0) : null, icon: const Icon(Icons.first_page)),
            IconButton(tooltip: 'Anterior', onPressed: _page > 0 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left)),
            Text('$first–$last de ${widget.items.length}', style: t.textTheme.titleSmall),
            IconButton(tooltip: 'Siguiente', onPressed: _page < pages - 1 ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right)),
            IconButton(tooltip: 'Última página', onPressed: _page < pages - 1 ? () => setState(() => _page = pages - 1) : null, icon: const Icon(Icons.last_page)),
          ]));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
