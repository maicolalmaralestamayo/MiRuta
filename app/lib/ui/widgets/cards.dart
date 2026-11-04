import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/templates.dart';
import '../theme.dart';
import 'common.dart' show plural;

/// Tarjetas modelo de toda la app (docs/11 §11.3, §11.10 y §11.18; maquetas
/// pantallas-final.png e inicio-propuesta-3.png). Una tarjeta es una vista
/// resumida y compacta: sin nombres de campos ni botones dentro.
///
/// - [InfoCard] es la tarjeta genérica: imágenes a la izquierda (o a la
///   derecha), un título y líneas que se cortan con «…».
/// - Las demás (UserCard, ChildCard, EntityCard, ItineraryStopCard,
///   RoleCard) son la forma acordada de cada objeto. Úselas siempre que se
///   muestre ese objeto.
///
/// Selección: `selected: true` marca la tarjeta con ✓ (modo selección de
/// [SelectableCardList]); `dim: true` la atenúa (desactivada).

/// Imagen cuadrada (o redonda) de una tarjeta. Sin imagen, un ícono.
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
    final fallback = Icon(icon, size: size * 0.55, color: scheme.primary);
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(round ? size : 10),
        child: Container(
          width: size,
          height: size,
          color: scheme.primaryContainer,
          child: provider == null ? fallback : Image(image: provider, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
        ),
      ),
    );
  }
}

/// Etiqueta de estado pequeña junto al título («Pendiente», «En curso»).
class CardChip extends StatelessWidget {
  final String text;
  final Color color;

  const CardChip(this.text, {super.key, this.color = Colors.green});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Título pequeño encima de un grupo de tarjetas («Hijos», «Entidad»…).
class SectionHeader extends StatelessWidget {
  final String text;

  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Tarjeta genérica.
class InfoCard extends StatelessWidget {
  /// Una o varias imágenes (normalmente [CardImage]).
  final List<Widget> images;

  /// Imágenes a la derecha (tarjeta de hijo).
  final bool imagesRight;
  final String title;
  final List<String> lines;

  /// Etiqueta junto al título ([CardChip]).
  final Widget? chip;

  /// Al final (↕ del selector de Entidad, ✓ de la hoja «Mis Entidades»).
  final Widget? trailing;

  /// Atenuada (desactivada).
  final bool dim;

  /// Marcada en modo selección: fondo de color, borde y ✓.
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const InfoCard({
    super.key,
    this.images = const [],
    this.imagesRight = false,
    required this.title,
    this.lines = const [],
    this.chip,
    this.trailing,
    this.dim = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant.withValues(alpha: dim ? 0.6 : 1));
    Widget line(String text, TextStyle style) => Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    Widget media = Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < images.length; i++) ...[if (i > 0) const SizedBox(width: 6), images[i]],
    ]);
    final check = Container(
      decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: Icon(Icons.check, size: 18, color: t.colorScheme.onPrimary),
    );
    if (selected) {
      // El ✓ va sobre la imagen; sin imagen, en su lugar.
      media = images.isEmpty ? check : Stack(clipBehavior: Clip.none, children: [media, Positioned(right: -4, top: -4, child: check)]);
    }
    final text = Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: line(title, t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: dim ? t.disabledColor : null))),
          if (chip != null) ...[const SizedBox(width: 6), chip!],
        ]),
        const SizedBox(height: 2),
        for (final l in lines) line(l, muted),
      ]),
    );
    final hasMedia = images.isNotEmpty || selected;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      color: selected ? t.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? t.colorScheme.primary : t.colorScheme.outline, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (hasMedia && !imagesRight) ...[media, const SizedBox(width: 14)],
            text,
            if (hasMedia && imagesRight) ...[const SizedBox(width: 12), media],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// Tarjeta de usuario (docs/11 §11.3): foto (o ícono de persona), nombres y
/// apellidos y las abreviaturas de sus Entidades separadas por • (o «Sin Entidad»).
class UserCard extends StatelessWidget {
  final String fullName;
  final String? photoUrl;
  final List<String> entities;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UserCard({super.key, required this.fullName, this.photoUrl, this.entities = const [], this.selected = false, this.dim = false, this.onTap, this.onLongPress});

  /// De una persona (`users`).
  UserCard.person(Person person, {super.key, this.selected = false, this.onTap, this.onLongPress})
      : fullName = person.fullName,
        photoUrl = person.photoUrl,
        entities = person.entities,
        dim = !person.active;

  /// De una pertenencia (`workers`): la Entidad es la de la pertenencia.
  UserCard.worker(Worker worker, {super.key, this.selected = false, this.onTap, this.onLongPress})
      : fullName = worker.fullName,
        photoUrl = worker.photoUrl,
        entities = [if (worker.entity != null) worker.entity!.abbreviation],
        dim = !worker.active;

  @override
  Widget build(BuildContext context) => InfoCard(
        images: [CardImage(url: photoUrl, icon: Icons.person, round: true, size: 60, dim: dim)],
        title: fullName,
        lines: [entities.isEmpty ? 'Sin Entidad' : entities.join(' • ')],
        dim: dim,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );
}

/// Tarjeta de hijo (docs/11 §11.10): foto a la derecha; nombres y apellidos,
/// «Nacimiento dd/mm/aa» y «Derecho dd/mm/aa» (o «Desactivado», atenuada).
class ChildCard extends StatelessWidget {
  final Child child;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChildCard(this.child, {super.key, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final dim = !child.active;
    return InfoCard(
      imagesRight: true,
      images: [CardImage(url: child.photoUrl, icon: Icons.face, round: true, dim: dim)],
      title: child.fullName,
      lines: [
        'Nacimiento ${formatShortDay(child.birthDate)}',
        if (!child.active) 'Desactivado' else if (!child.eligible) 'Sin derecho a viajar' else 'Derecho ${formatShortDay(child.eligibleUntil)}',
      ],
      dim: dim,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Tarjeta de Entidad (docs/11 §11.10): imagen; abreviatura, nombre y
/// «N trabajadores». [selector] añade ↕ (abre «Mis Entidades»); [checked]
/// añade el ✓ verde de la elegida en esa hoja.
class EntityCard extends StatelessWidget {
  final Entity? entity;
  final bool selector;
  final bool checked;

  /// Línea extra (p. ej. «Solicitada el mar. 03/11/26»).
  final String? extraLine;
  final Widget? chip;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const EntityCard(this.entity, {super.key, this.selector = false, this.checked = false, this.extraLine, this.chip, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final e = entity;
    return InfoCard(
      images: [CardImage(url: e?.imageUrl, icon: Icons.apartment)],
      title: e?.abbreviation ?? 'Sin Entidad',
      lines: e == null
          ? ['Toque aquí para solicitar entrar en una Entidad']
          : [if (e.name.isNotEmpty) e.name, plural(e.workerCount, 'trabajador', 'trabajadores'), ?extraLine],
      chip: chip,
      trailing: checked
          ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
          : (selector && e != null ? const Icon(Icons.unfold_more) : null),
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Tarjeta de itinerario y parada (docs/11 §11.10): las dos imágenes juntas;
/// nombre del itinerario, «calle • punto de referencia» y «N trabajadores».
/// Sin itinerario: tarjeta «Sin itinerario».
class ItineraryStopCard extends StatelessWidget {
  final String? itineraryName;
  final String? itineraryImageUrl;
  final String? street;
  final String? landmark;
  final String? stopImageUrl;
  final int? memberCount;
  final String? extraLine;
  final Widget? chip;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ItineraryStopCard({
    super.key,
    this.itineraryName,
    this.itineraryImageUrl,
    this.street,
    this.landmark,
    this.stopImageUrl,
    this.memberCount,
    this.extraLine,
    this.chip,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  /// La de una pertenencia (Inicio, «Itinerario y parada»). Sin itinerario: «Sin itinerario».
  ItineraryStopCard.membership(Membership? membership, {super.key, this.selected = false, this.onTap, this.onLongPress})
      : itineraryName = membership?.itinerary?.name,
        itineraryImageUrl = membership?.itinerary?.imageUrl,
        street = membership?.stop?.street,
        landmark = membership?.stop?.landmark,
        stopImageUrl = membership?.stop?.imageUrl,
        memberCount = membership?.itinerary?.memberCount,
        extraLine = null,
        chip = null;

  @override
  Widget build(BuildContext context) {
    final none = itineraryName == null;
    return InfoCard(
      images: [CardImage(url: itineraryImageUrl, icon: Icons.route), CardImage(url: stopImageUrl, icon: Icons.place)],
      title: none ? 'Sin itinerario' : itineraryName!,
      lines: none
          ? ['Toque aquí para solicitar itinerario y parada']
          : [
              [street, landmark].where((s) => s != null && s.isNotEmpty).join(' • '),
              if (memberCount != null) plural(memberCount!, 'trabajador', 'trabajadores'),
              ?extraLine,
            ],
      chip: chip,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Tarjeta de rol (docs/11 §11.10): ícono; el rol y, debajo, el nombre del
/// itinerario (Jefe de itinerario) o la abreviatura de la Entidad.
class RoleCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? icon;
  final String? extraLine;
  final Widget? chip;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const RoleCard({super.key, required this.name, required this.subtitle, this.icon, this.extraLine, this.chip, this.selected = false, this.onTap, this.onLongPress});

  /// La tarjeta «Trabajador» (siempre la primera en Roles).
  RoleCard.worker(Entity entity, {super.key, this.selected = false, this.onTap, this.onLongPress})
      : name = 'Trabajador',
        subtitle = entity.abbreviation,
        icon = 'badge',
        extraLine = null,
        chip = null;

  /// Un rol aprobado en esa Entidad.
  RoleCard.held(HeldRole role, Entity entity, {super.key, this.selected = false, this.onTap, this.onLongPress})
      : name = role.name,
        subtitle = role.itineraryName ?? entity.abbreviation,
        icon = role.icon,
        extraLine = null,
        chip = null;

  @override
  Widget build(BuildContext context) => InfoCard(
        images: [CardImage(icon: roleIcon(icon))],
        title: name,
        lines: [subtitle, ?extraLine],
        chip: chip,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
      );
}

/// Ícono Material de un rol a partir de su nombre (`roles.icon`).
IconData roleIcon(String? name) => const {
      'badge': Icons.badge_outlined,
      'route': Icons.groups,
      'groups': Icons.groups,
      'directions_bus': Icons.airline_seat_recline_normal,
      'airline_seat_recline_normal': Icons.airline_seat_recline_normal,
      'manage_accounts': Icons.manage_accounts,
      'admin_panel_settings': Icons.admin_panel_settings,
      'person': Icons.person,
      'support_agent': Icons.support_agent,
      'local_shipping': Icons.local_shipping,
      'engineering': Icons.engineering,
      'verified_user': Icons.verified_user,
    }[name] ??
    Icons.work_outline;

/// Color del estado de una solicitud, para su [CardChip].
Color applicationStatusColor(String status) => const {
      ApplicationStatus.pending: orange,
      ApplicationStatus.approved: Color(0xFF2E7D32),
      ApplicationStatus.rejected: overloadColor,
    }[status] ?? Colors.grey;
