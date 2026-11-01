import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/geo.dart';
import '../../services/templates.dart';
import '../theme.dart';

/// Línea con hitos (docs/09 §19): la línea vertical va centrada en la pantalla
/// y ocupa siempre el alto disponible; las paradas son puntos gruesos encima
/// de ella, separados en proporción a la distancia real entre ellas. Junto al
/// nombre de cada parada van la hora de paso y los km desde la anterior; las
/// paradas donde no se detuvo o que se saltó van marcadas.
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
    final passes = {for (final pass in leg.stopPasses) pass.stopId: pass};
    final vehicle = _vehicleFraction(cumulative, total, passes);
    final colors = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;

    return LayoutBuilder(builder: (context, constraints) {
      const margin = 28.0;
      final available = constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
      final fullHeight = available < 220 ? 220.0 : available;
      final height = fullHeight - margin * 2;
      final center = constraints.maxWidth / 2;
      double y(double fraction) => margin + fraction * height;

      Widget label(int i, bool right) {
        final stop = stops[i];
        final pass = passes[stop.id];
        final extra = [
          if (pass != null && !pass.skipped) formatTime(pass.passedAt),
          if (i > 0) '${((cumulative[i] - cumulative[i - 1]) / 1000).toStringAsFixed(1)} km',
          if (pass != null && pass.notStopped) 'No se detuvo',
          if (pass != null && pass.skipped) 'Saltada',
        ].join(' · ');
        final mark = _markColor(pass, colors);
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: stop.landmark, style: TextStyle(fontWeight: stop.id == highlightStopId ? FontWeight.bold : FontWeight.w500)),
            if (extra.isNotEmpty) TextSpan(text: '  $extra', style: small?.copyWith(color: pass != null && (pass.skipped || pass.notStopped) ? mark : null)),
          ]),
          textAlign: right ? TextAlign.left : TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      }

      return SingleChildScrollView(
        physics: available < 220 ? null : const NeverScrollableScrollPhysics(),
        child: SizedBox(
          height: fullHeight,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: center - 3, top: y(0), height: height, width: 6, child: Container(color: colors.outlineVariant)),
            if (vehicle != null) Positioned(left: center - 3, top: y(0), height: vehicle * height, width: 6, child: Container(color: colors.primary)),
            for (var i = 0; i < stops.length; i++) ...[
              // Nombre, hora y km a un lado de la línea (alternando para que no se monten).
              if (i.isEven)
                Positioned(left: center + 20, right: 8, top: y(cumulative[i] / total) - 10, child: label(i, true))
              else
                Positioned(left: 8, right: center + 20, top: y(cumulative[i] / total) - 10, child: label(i, false)),
              Positioned(
                left: center - 12,
                top: y(cumulative[i] / total) - 12,
                child: _Dot(pass: passes[stops[i].id], color: _markColor(passes[stops[i].id], colors), highlight: stops[i].id == highlightStopId),
              ),
            ],
            if (vehicle != null && leg.isActive)
              Positioned(
                left: center - 16,
                top: y(vehicle) - 16,
                child: CircleAvatar(radius: 16, backgroundColor: colors.primary, child: const Icon(Icons.directions_bus, size: 18, color: Colors.white)),
              ),
          ]),
        ),
      );
    });
  }

  static Color _markColor(StopPass? pass, ColorScheme colors) {
    if (pass == null) return colors.outline;
    if (pass.skipped) return overloadColor;
    if (pass.notStopped) return saturatedColor;
    return colors.primary;
  }

  /// Fracción del recorrido: última parada pasada + avance hacia la siguiente.
  double? _vehicleFraction(List<double> cumulative, double total, Map<String, StopPass> passes) {
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

/// Punto grueso de la parada, encima de la línea.
class _Dot extends StatelessWidget {
  final StopPass? pass;
  final Color color;
  final bool highlight;

  const _Dot({required this.pass, required this.color, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final p = pass;
    final icon = p == null
        ? null
        : p.skipped
            ? Icons.close
            : p.notStopped
                ? Icons.fast_forward
                : Icons.check;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: p == null ? Theme.of(context).colorScheme.surface : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: highlight ? 5 : 4),
      ),
      child: icon == null ? null : Icon(icon, size: 14, color: Colors.white),
    );
  }
}
