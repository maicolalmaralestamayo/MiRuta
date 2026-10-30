import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/geo.dart';
import '../../services/templates.dart';

/// Línea con hitos proporcional a la distancia real (docs/07-algoritmos.md §7.25):
/// la separación entre paradas en pantalla es proporcional a la distancia entre ellas.
class ProportionalTimeline extends StatelessWidget {
  final List<Stop> stops;
  final TripLeg leg;
  final String? highlightStopId;

  const ProportionalTimeline({super.key, required this.stops, required this.leg, this.highlightStopId});

  @override
  Widget build(BuildContext context) {
    if (stops.length < 2) return const Center(child: Text('El itinerario necesita al menos dos paradas.'));

    final cumulative = <double>[0];
    for (var i = 1; i < stops.length; i++) {
      cumulative.add(cumulative.last + distanceMeters(stops[i - 1].latitude, stops[i - 1].longitude, stops[i].latitude, stops[i].longitude));
    }
    final total = cumulative.last == 0 ? 1.0 : cumulative.last;
    final passes = {for (final pass in leg.stopPasses) pass.stopId: pass.passedAt};
    final vehicle = _vehicleFraction(cumulative, total, passes);
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      const top = 24.0;
      final height = (constraints.maxHeight - top * 2).clamp(200.0, 4000.0);
      double y(double fraction) => top + fraction * height;

      return SingleChildScrollView(
        child: SizedBox(
          height: height + top * 2,
          child: Stack(children: [
            Positioned(left: 39, top: y(0), height: height, width: 4, child: Container(color: colors.outlineVariant)),
            if (vehicle != null) Positioned(left: 39, top: y(0), height: vehicle * height, width: 4, child: Container(color: colors.primary)),
            for (var i = 0; i < stops.length; i++)
              Positioned(
                left: 0,
                right: 8,
                top: y(cumulative[i] / total) - 14,
                child: Row(children: [
                  const SizedBox(width: 28),
                  Icon(passes.containsKey(stops[i].id) ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 26, color: passes.containsKey(stops[i].id) ? colors.primary : colors.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stops[i].landmark,
                      style: TextStyle(fontWeight: stops[i].id == highlightStopId ? FontWeight.bold : null),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (passes.containsKey(stops[i].id)) Text(formatTime(passes[stops[i].id]!), style: Theme.of(context).textTheme.bodySmall),
                  if (i > 0) Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${((cumulative[i] - cumulative[i - 1]) / 1000).toStringAsFixed(1)} km', style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ),
            if (vehicle != null && leg.isActive)
              Positioned(
                left: 25,
                top: y(vehicle) - 16,
                child: CircleAvatar(radius: 16, backgroundColor: colors.primary, child: const Icon(Icons.directions_bus, size: 18, color: Colors.white)),
              ),
          ]),
        ),
      );
    });
  }

  /// Fracción del recorrido: última parada pasada + avance hacia la siguiente.
  double? _vehicleFraction(List<double> cumulative, double total, Map<String, DateTime> passes) {
    var last = -1;
    for (var i = 0; i < stops.length; i++) {
      if (passes.containsKey(stops[i].id)) last = i;
    }
    if (last < 0 && leg.latitude == null) return null;
    if (last < 0) last = 0;
    if (last >= stops.length - 1 || leg.latitude == null) return cumulative[last] / total;

    final segment = cumulative[last + 1] - cumulative[last];
    final advance = distanceMeters(stops[last].latitude, stops[last].longitude, leg.latitude!, leg.longitude!).clamp(0.0, segment);
    return (cumulative[last] + advance) / total;
  }
}
