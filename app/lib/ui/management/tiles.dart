import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../models/models.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Tarjetas de Gestión, de Inicio y de los formularios (maquetas G19, G20 y
/// G22): tocar abre el objeto; mantener lo marca (donde se puede marcar).

String _requests(int n) => n == 1 ? '1 solicitud' : '$n solicitudes';

Widget entityTile(Entity e, {bool selected = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: e.imageUrl, icon: Icons.apartment, dim: !e.active)],
      title: e.abbreviation,
      lines: ['${e.name} • ${plural(e.itineraryCount, 'itinerario', 'itinerarios')} • ${plural(e.workerCount, 'trabajador', 'trabajadores')}'],
      chip: !e.active ? const Chip2('Desactivada', grey) : (e.pendingApplications > 0 ? Chip2(_requests(e.pendingApplications), amber) : null),
      dim: !e.active,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

Widget itineraryTile(Itinerary i, {bool selected = false, bool chief = false, bool showEntity = true, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: i.imageUrl, icon: Icons.route, dim: !i.active)],
      title: i.name,
      lines: [
        [
          if (showEntity) i.entityAbbreviation ?? (i.entityId == null ? 'Sin Entidad' : ''),
          plural(i.stopCount, 'parada', 'paradas'),
          plural(i.workerCount, 'trabajador', 'trabajadores'),
        ].where((p) => p.isNotEmpty).join(' • '),
      ],
      chip: !i.active
          ? const Chip2('Desactivado', grey)
          : (i.pendingApplications > 0 ? Chip2(_requests(i.pendingApplications), amber) : (chief ? const Chip2('Jefe', green) : null)),
      dim: !i.active,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

Widget stopTile(Stop s, {int? position, bool selected = false, Widget? trailing, VoidCallback? onTap, VoidCallback? onLongPress, String? extra}) => InfoCard(
      images: [CardImage(url: s.imageUrl, icon: Icons.place, dim: !s.active)],
      title: position == null ? s.landmark : '$position. ${s.landmark}',
      lines: [extra ?? [s.address, if (position == null) plural(s.itineraries.length, 'itinerario', 'itinerarios')].where((p) => p.isNotEmpty).join(' • ')],
      chip: s.active ? null : const Chip2('Desactivada', grey),
      dim: !s.active,
      selected: selected,
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );

/// Persona (recurso users): «usuario • CI …» o sus Entidades.
Widget personTile(Person p, {bool selected = false, String? line, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: p.photoUrl, icon: Icons.person, round: true)],
      title: p.fullName,
      lines: [
        line ??
            [
              p.username ?? '',
              if (p.identityCard != null) 'CI ${p.identityCard}',
              if (p.username == null && p.identityCard == null) p.entities.isEmpty ? 'Sin Entidad' : p.entities.join(', '),
            ].where((s) => s.isNotEmpty).join(' • '),
      ],
      chip: p.isAdmin ? const Chip2('Admin.', blue2) : null,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

/// La persona en una Entidad: sus itinerarios y paradas allí.
Widget workerTile(Worker w, {bool selected = false, bool showEntity = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: w.person.photoUrl, icon: Icons.person, round: true, dim: !w.active)],
      title: w.person.fullName,
      lines: [[if (showEntity) w.entityAbbreviation ?? '', w.where].where((p) => p.isNotEmpty).join(' • ')],
      chip: !w.active ? const Chip2('Desactivado', grey) : (w.isChief ? const Chip2('Jefe', green) : null),
      dim: !w.active,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

/// La persona en un itinerario (formularios de itinerario y parada, «sin parada»).
Widget placementPersonTile(Placement p, {String? line, bool selected = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: p.photoUrl, icon: Icons.person, round: true, dim: !p.active)],
      title: p.userName ?? '',
      lines: [line ?? (p.stopLandmark ?? 'Sin parada')],
      chip: !p.active ? const Chip2('Desactivado', grey) : (p.isChief ? const Chip2('Jefe', green) : null),
      dim: !p.active,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

/// Uno de los itinerarios de una persona (formulario del Trabajador e Inicio), con su parada.
Widget placementTile(Placement p, {bool indent = false, bool showEntity = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [CardImage(url: p.itineraryImageUrl, icon: Icons.route, dim: !p.itineraryActive)],
      title: p.itineraryName,
      lines: [[if (showEntity) p.entityAbbreviation, p.stopLandmark == null ? 'Sin parada' : 'Parada: ${p.stopLandmark}'].where((s) => s.isNotEmpty).join(' • ')],
      chip: p.isChief ? const Chip2('Jefe', green) : null,
      margin: EdgeInsets.fromLTRB(indent ? 36 : 12, 4, 12, 4),
      onTap: onTap,
      onLongPress: onLongPress,
    );

/// Una de las Entidades de una persona.
Widget membershipTile(Membership m, {VoidCallback? onTap}) => InfoCard(
      images: [CardImage(url: m.entityImageUrl, icon: Icons.apartment, dim: !m.active)],
      title: m.entityAbbreviation,
      lines: [m.itineraries.isEmpty ? '${m.entityName} • Sin itinerario' : m.entityName],
      chip: m.active ? null : const Chip2('Desactivado', grey),
      dim: !m.active,
      onTap: onTap,
    );

Color applicationColor(Application a) => switch (a.status) { 'aprobada' => green, 'rechazada' => red, _ => amber };

/// Solicitud: la propia («Ruta Este (ESM) • Pendiente») o la de otra persona.
Widget applicationTile(Application a, {required bool mine, bool selected = false, VoidCallback? onTap, VoidCallback? onLongPress}) => InfoCard(
      images: [mine ? CardImage(icon: a.isEntity ? Icons.apartment : Icons.route) : const CardImage(icon: Icons.person, round: true)],
      title: mine ? (a.isEntity ? a.entityAbbreviation ?? 'Entidad' : '${a.itineraryName ?? ''}${a.entityAbbreviation == null ? '' : ' (${a.entityAbbreviation})'}') : (a.userName ?? 'Solicitud'),
      lines: [
        if (a.status == 'rechazada' && a.denialReason != null)
          'Rechazada: ${a.denialReason}'
        else if (mine)
          [if (!a.isEntity) a.stopLandmark == null ? 'Sin parada' : 'Parada: ${a.stopLandmark}', formatDate(a.createdAt)].join(' • ')
        else
          'Pide ${a.isEntity ? 'entrar en ${a.entityAbbreviation ?? ''}' : '${a.itineraryName ?? ''}${a.stopLandmark == null ? '' : ' • parada ${a.stopLandmark}'}'} • ${formatDate(a.createdAt)}',
      ],
      chip: Chip2(a.statusName, applicationColor(a)),
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );

Widget childTile(Child c, {VoidCallback? onTap}) => InfoCard(
      images: [CardImage(url: c.photoUrl, icon: Icons.child_care, round: true, dim: !c.canTravel)],
      title: c.fullName,
      lines: ['Fecha nac.: ${formatDate(c.birthDate)}', c.eligible ? 'Derecho a viajar: ${formatDate(c.eligibleUntil)}' : 'Sin derecho a viajar'],
      chip: c.active ? null : const Chip2('Desactivado', grey),
      dim: !c.canTravel,
      onTap: onTap,
    );

/// Botón de una relación («Asociar Entidad», «Adicionar parada»…), a lo ancho y sin relleno.
class RelationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool indent;

  const RelationButton(this.icon, this.label, this.onPressed, {super.key, this.indent = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(indent ? 36 : 12, 6, 12, 6),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 20), label: Text(label)),
        ),
      );
}

/// Aviso dentro de una sección (p. ej. «Guarde primero…»).
class HintText extends StatelessWidget {
  final String text;

  const HintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
}
