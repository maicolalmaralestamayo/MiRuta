import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formats.dart';
import '../../models/models.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

Color tripStatusColor(String status) => switch (status) {
      TripStatus.running => green,
      TripStatus.finished => grey,
      TripStatus.cancelled => red,
      _ => blue2,
    };

/// Viajes con el nombre de la parada de salida de cada uno.
class TripList {
  final List<Trip> trips;

  /// Itinerario → (primera parada, última parada).
  final Map<String, (String, String)> ends;

  const TripList(this.trips, this.ends);

  /// Parada de salida: la primera en la ida y la última en el regreso.
  String? departureOf(Trip t) {
    final e = ends[t.itineraryId];
    return e == null ? null : (t.outbound ? e.$1 : e.$2);
  }

  static Future<TripList> load(ApiClient api, Map<String, dynamic> query) async {
    final trips = (await api.getAll('/trips', query: {'include': 'itinerary,vehicleType', 'sort': 'departsAt', ...query})).map(Trip.from).toList();
    final ends = <String, (String, String)>{};
    for (final id in trips.map((t) => t.itineraryId).toSet()) {
      try {
        final stops = (await api.getAll('/stops', query: {'filter[itinerary]': id, 'sort': 'position'})).map(Stop.from).toList();
        if (stops.isNotEmpty) ends[id] = (stops.first.landmark, stops.last.landmark);
      } catch (_) {}
    }
    return TripList(trips, ends);
  }
}

/// Tarjeta de un viaje: «Ruta Playa • Ida • sáb. 07-11-26», salida, vehículo y ocupación.
class TripCard extends StatelessWidget {
  final Trip trip;
  final String? departure;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TripCard({super.key, required this.trip, this.departure, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final started = t.isRunning || t.status == TripStatus.finished;
    final time = started && t.statusChangedAt != null && t.isRunning ? formatTime(t.statusChangedAt) : t.departureTime;
    return InfoCard(
      images: [CardImage(icon: t.outbound ? Icons.east : Icons.west)],
      title: '${t.itineraryName ?? 'Viaje'} • ${t.directionName} • ${formatDate(t.date)}',
      lines: [
        '${started ? 'Salió' : 'Sale'} $time${departure == null ? '' : ' de $departure'}',
        '${t.vehicleTypeName ?? 'Vehículo'} • ${t.occupancy}',
      ],
      chip: Chip2(TripStatus.name(t.status), tripStatusColor(t.status)),
      dim: t.status == TripStatus.cancelled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
