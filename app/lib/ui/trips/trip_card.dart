import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/templates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'trip_detail_screen.dart';

/// Tarjeta de un viaje. La sobresaturación se resalta solo para los jefes.
class TripCard extends StatelessWidget {
  final Trip trip;
  final bool showOverload;
  final VoidCallback? onChanged;
  final Widget? leading;
  final VoidCallback? onTap;

  /// Tramos del viaje (viaje de ida / de regreso) para mostrar el estado del
  /// recorrido. Sin ellos se muestra al menos el atraso.
  final List<TripLeg>? legs;

  const TripCard({super.key, required this.trip, this.showOverload = false, this.onChanged, this.leading, this.onTap, this.legs});

  @override
  Widget build(BuildContext context) {
    // Saturado (naranja) o sobresaturado (rojo): docs/08-version-2.md §8.9.
    final levelColor = showOverload ? occupancyColor(trip.occupancyLevel) : null;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      shape: levelColor != null ? RoundedRectangleBorder(side: BorderSide(color: levelColor, width: 2), borderRadius: BorderRadius.circular(12)) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ??
            () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)));
              onChanged?.call();
            },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(trip.itineraryName ?? 'Viaje', style: Theme.of(context).textTheme.titleMedium)),
                  StatusChip(TripStatus.label(trip.status), color: tripStatusColor(trip.status)),
                ]),
                TripLegsStatus(trip: trip, legs: legs),
                const SizedBox(height: 4),
                Text(
                  [
                    if (trip.vehicleTypeName != null) trip.vehicleTypeName!,
                    if (trip.vehiclePlate != null) formatPlate(trip.vehiclePlate),
                    if (trip.driverName != null) 'Chofer: ${trip.driverName}',
                  ].join(' · '),
                  style: small,
                ),
                if (showOverload) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.people_alt_outlined, size: 16, color: levelColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(occupancyText(trip.expectedPassengers, trip.expectedChildren, trip.totalCapacity),
                          style: TextStyle(color: levelColor, fontWeight: levelColor != null ? FontWeight.bold : null)),
                    ),
                    if (levelColor != null) ...[
                      const SizedBox(width: 6),
                      StatusChip(occupancyLabel(trip.occupancyLevel), color: levelColor),
                    ],
                    if (trip.needsReassignment) ...[
                      const SizedBox(width: 8),
                      const StatusChip('Sin chofer', color: overloadColor, icon: Icons.person_off),
                    ],
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Viaje de ida (fecha)" y "Viaje de regreso (fecha)", cada uno con el estado
/// de su recorrido (docs/09 §8 y Viajes atrasados): en curso, completado,
/// atrasado o comenzado con atraso.
class TripLegsStatus extends StatelessWidget {
  final Trip trip;
  final List<TripLeg>? legs;

  const TripLegsStatus({super.key, required this.trip, this.legs});

  TripLeg? _leg(String direction) {
    for (final leg in legs ?? const <TripLeg>[]) {
      if (leg.direction == direction) return leg;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final direction in const ['outbound', 'return']) _line(context, direction),
    ]);
  }

  Widget _line(BuildContext context, String direction) {
    final outbound = direction == 'outbound';
    final chips = tripLegChips(context, trip, _leg(direction), direction);
    final minutes = outbound ? trip.outboundDelayMinutes : trip.returnDelayMinutes;
    final startedLate = tripLegStartedLate(trip, direction);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(outbound ? Icons.north_east : Icons.south_west, size: 16),
            const SizedBox(width: 4),
            Text('${TripLeg.directionName(direction)} ${formatDateTime(outbound ? trip.departsAt : trip.returnsAt)}'),
          ]),
          ...chips,
        ]),
        if (startedLate)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text('Comenzó con $minutes min de atraso', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: overloadColor)),
          ),
      ]),
    );
  }
}

/// Estado del recorrido de un tramo: en curso ("Viaje de ida"), completado o atrasado.
List<Widget> tripLegChips(BuildContext context, Trip trip, TripLeg? leg, String direction) {
  final outbound = direction == 'outbound';
  final delayed = outbound ? trip.outboundDelayed : trip.returnDelayed;
  final minutes = outbound ? trip.outboundDelayMinutes : trip.returnDelayMinutes;
  return [
    if (leg != null && leg.isActive) StatusChip(TripLeg.directionName(direction), color: Theme.of(context).colorScheme.primary, icon: Icons.radar),
    if (leg != null && !leg.isActive) StatusChip(outbound ? 'Ida completada' : 'Regreso completado', color: Colors.green, icon: Icons.check_circle),
    if (delayed) StatusChip(minutes == null ? 'Atrasado' : 'Atrasado $minutes min', color: overloadColor, icon: Icons.schedule),
  ];
}

/// Ya comenzó, pero con atraso (el servidor da los minutos aunque ya no esté atrasado).
bool tripLegStartedLate(Trip trip, String direction) {
  final outbound = direction == 'outbound';
  final delayed = outbound ? trip.outboundDelayed : trip.returnDelayed;
  final minutes = outbound ? trip.outboundDelayMinutes : trip.returnDelayMinutes;
  return !delayed && minutes != null && minutes > 0;
}
