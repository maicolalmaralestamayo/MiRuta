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

  const TripCard({super.key, required this.trip, this.showOverload = false, this.onChanged, this.leading, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Saturado (naranja) o sobresaturado (rojo): docs/08-version-2.md §8.9.
    final levelColor = showOverload ? occupancyColor(trip.occupancyLevel) : null;
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
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.north_east, size: 16),
                  const SizedBox(width: 4),
                  Text('Salida ${formatDateTime(trip.departsAt)}'),
                ]),
                Row(children: [
                  const Icon(Icons.south_west, size: 16),
                  const SizedBox(width: 4),
                  Text('Regreso ${formatDateTime(trip.returnsAt)}'),
                ]),
                const SizedBox(height: 4),
                Text(
                  [
                    if (trip.vehicleTypeName != null) trip.vehicleTypeName!,
                    if (trip.vehiclePlate != null) trip.vehiclePlate!,
                    if (trip.driverName != null) 'Chofer: ${trip.driverName}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
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
