import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formats.dart';
import '../../models/models.dart';
import '../../services/notification_texts.dart';
import '../widgets/app_icon.dart';
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

/// Las líneas de la tarjeta de un viaje, con el formato de su notificación
/// (docs/11 §11.63 y §11.67). Código puro (se prueba en test/):
///
/// ```
/// Viaje [planificado | cambiado | en ejecución | terminado | cancelado]
/// [Itinerario] • [ida | regreso] • [Jue. 19/11/26 10:30]
/// [Parada de salida] • [Tipo de vehículo]
/// [naranja, si cambió y sigue Planificado: Cambió la hora]
/// ```
class TripCardText {
  final String title;
  final String route;
  final String details;
  final String? highlight;

  const TripCardText(this.title, this.route, this.details, this.highlight);

  factory TripCardText.of(Trip t, {String? departure}) {
    final changed = t.isPlanned && t.changes.isNotEmpty;
    final status = changed
        ? 'cambiado'
        : switch (t.status) {
            TripStatus.running => 'en ejecución',
            TripStatus.finished => 'terminado',
            TripStatus.cancelled => 'cancelado',
            _ => 'planificado',
          };
    return TripCardText(
      'Viaje $status',
      // El viaje de prueba del simulador se ve como «Simulación» (docs/11 §11.66).
      '${t.simulation ? 'Simulación • ' : ''}${itineraryLine(t.itineraryName, t.direction)} • ${formatDayTime(t.date, t.departureTime)}',
      [departure ?? 'Parada de salida', t.vehicleTypeName ?? 'Vehículo'].join(' • '),
      changed ? changesLine(t.changes) : null,
    );
  }
}

/// Tarjeta de un viaje con el formato de su notificación (docs/11 §11.67):
/// el icono de la app, «Viaje [estado]», itinerario, sentido, fecha y hora,
/// parada de salida y tipo de vehículo, y la línea naranja de cambios. Sin la
/// ocupación. [compact]: las 3 líneas, sin la de cambios (Ver recorrido).
class TripCard extends StatelessWidget {
  final Trip trip;
  final String? departure;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TripCard({super.key, required this.trip, this.departure, this.selected = false, this.compact = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final text = TripCardText.of(trip, departure: departure);
    return InfoCard(
      images: const [AppIcon(size: 48)],
      title: text.title,
      lines: [text.route, text.details],
      highlight: compact ? null : text.highlight,
      dim: trip.status == TripStatus.cancelled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Nombre propio de la acción y su spinner: («Iniciar», «Iniciando»).
(String, String) tripStatusVerb(String status) => switch (status) {
      TripStatus.running => ('Iniciar', 'Iniciando'),
      TripStatus.finished => ('Terminar', 'Terminando'),
      _ => ('Cancelar', 'Cancelando'),
    };
