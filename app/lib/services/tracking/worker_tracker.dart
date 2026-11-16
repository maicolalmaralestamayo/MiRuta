/// Estado del trabajador y del vehículo calculados EN EL TELÉFONO (docs/11
/// §11.43, §11.44 y §11.65). Código puro, sin plugins: se prueba en test/.
///
/// Desde la 4.4.0 el trabajador sube y baja en **cualquier parada**, en la ida
/// y en el regreso, y la app **detecta la parada por cercanía** a las paradas
/// del recorrido. Reglas (iguales en los dos sentidos):
///
/// - **De camino**: se mueve hacia una parada; «su parada» se recalcula en cada
///   cálculo como la más cercana a él de las que el vehículo aún no ha pasado.
/// - **En la parada**: dentro del radio de una parada que el vehículo aún no
///   ha pasado.
/// - **Viajando**: estaba En la parada y se aleja de ella a velocidad de
///   vehículo (más que la Velocidad humana): el vehículo llegó y subió.
/// - **No recogido**: estaba En la parada, el vehículo pasó por ella y él no
///   pasó a Viajando.
/// - **Retrasado**: estaba De camino y el vehículo pasó por su parada antes de
///   que llegara.
/// - **Dejado**: estaba Viajando y se separa del vehículo: «Cálculos
///   consecutivos» a velocidad humana en el radio de una parada, o mientras
///   los demás sensores dicen que el vehículo sigue; queda Dejado en la parada
///   más cercana.
/// - **No voy**: lo declara él, o se aleja de todas las paradas más allá de la
///   Distancia abandono.
/// - Finales: Dejado, No recogido, Retrasado y No voy (un No recogido que se
///   aleja a velocidad de vehículo antes de la Espera final sí subió: Viajando).
///
/// Viajando convierte el teléfono en sensor del vehículo: Detenido / En
/// movimiento (umbral: Tolerancia GPS), próxima parada y si está detenido en
/// su radio.
library;

import 'dart:math';

/// Punto con latitud y longitud.
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {'lat': latitude, 'lon': longitude};

  factory GeoPoint.fromJson(Map<String, dynamic> j) => GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());
}

/// Distancia en metros (haversine).
double distanceMeters(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * asin(min(1, sqrt(h)));
}

/// Ajustes del cálculo (grupo «Estado trabajador» y «Radio parada»).
class TrackerConfig {
  final double stopRadius;
  final double gpsTolerance;

  /// Metros por segundo.
  final double humanSpeed;
  final double abandonDistance;
  final int consecutive;
  final Duration finalWait;

  const TrackerConfig({
    this.stopRadius = 100,
    this.gpsTolerance = 20,
    this.humanSpeed = 10000 / 3600,
    this.abandonDistance = 1000,
    this.consecutive = 6,
    this.finalWait = const Duration(minutes: 10),
  });

  Map<String, dynamic> toJson() => {
        'stopRadius': stopRadius,
        'gpsTolerance': gpsTolerance,
        'humanSpeed': humanSpeed,
        'abandonDistance': abandonDistance,
        'consecutive': consecutive,
        'finalWaitSeconds': finalWait.inSeconds,
      };

  factory TrackerConfig.fromJson(Map<String, dynamic> j) => TrackerConfig(
        stopRadius: (j['stopRadius'] as num).toDouble(),
        gpsTolerance: (j['gpsTolerance'] as num).toDouble(),
        humanSpeed: (j['humanSpeed'] as num).toDouble(),
        abandonDistance: (j['abandonDistance'] as num).toDouble(),
        consecutive: (j['consecutive'] as num).toInt(),
        finalWait: Duration(seconds: (j['finalWaitSeconds'] as num).toInt()),
      );
}

/// Parada del recorrido (en el orden del recorrido del viaje).
class RouteStop {
  final String id;
  final String name;
  final GeoPoint point;

  const RouteStop(this.id, this.name, this.point);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, ...point.toJson()};

  factory RouteStop.fromJson(Map<String, dynamic> j) => RouteStop('${j['id']}', '${j['name'] ?? ''}', GeoPoint.fromJson(j));
}

/// Lo que se sabe del viaje por el servidor (respuesta del último envío).
class TripInfo {
  final String status;

  /// Posiciones del recorrido por las que ya pasó el vehículo.
  final Set<int> passed;

  /// Próxima parada según el servidor (0 = salida).
  final int nextStopIndex;

  /// Estado del vehículo por mayoría de los sensores (null = sin datos).
  final String? vehicleState;

  /// Sensores activos.
  final int sensors;

  const TripInfo({required this.status, this.passed = const {}, this.nextStopIndex = 0, this.vehicleState, this.sensors = 0});

  bool get closed => status == 'terminado' || status == 'cancelado';
}

/// Resultado de un cálculo.
class TrackerStep {
  /// Estado nuevo del trabajador (null si no cambió ni cambió su parada).
  final String? newState;

  /// La parada detectada del estado (en Dejado, donde se bajó; null en No voy).
  final String? stopId;

  /// Observación del sensor (solo si es sensor).
  final String? vehicleState;
  final int? nextStopIndex;
  final bool? atStop;

  /// Deja de calcular (estado final, espera final o viaje cerrado).
  final bool finished;

  const TrackerStep({this.newState, this.stopId, this.vehicleState, this.nextStopIndex, this.atStop, this.finished = false});

  bool get isSensor => vehicleState != null;
}

/// Máquina de estados del trabajador en un viaje (ida o regreso).
class WorkerTracker {
  final bool outbound;
  final List<RouteStop> route;
  final TrackerConfig config;

  // Estado (se guarda entre cálculos con toJson/fromJson).
  String? state;

  /// Posición en [route] de la parada del estado (detectada por cercanía).
  int? stopIndex;
  bool finished = false;
  GeoPoint? lastPoint;
  DateTime? lastTime;
  int slowCount = 0;
  DateTime? waitingSince;

  /// Parada donde subió (Viajando).
  int? boardIndex;

  // Sensor
  int sensorNext = 1;
  bool enteredNext = false;
  double? prevNextDistance;
  double? prevAfterNextDistance;

  WorkerTracker({required this.outbound, required this.route, this.config = const TrackerConfig()});

  static const states = ['de_camino', 'en_parada', 'viajando', 'dejado', 'no_recogido', 'retrasado', 'no_voy'];

  /// Estados finales (docs/11 §11.65).
  static const finalStates = {'dejado', 'no_recogido', 'retrasado', 'no_voy'};

  /// Nombres de versiones anteriores (servidor viejo o datos guardados).
  static String? normalize(String? s) => switch (s) { 'recogido' => 'viajando', 'botado' => 'no_recogido', 'dormido' => 'retrasado', _ => s };

  bool get isSensor => state == 'viajando';

  String? get stopId => stopIndex == null || stopIndex! < 0 || stopIndex! >= route.length ? null : route[stopIndex!].id;

  /// Nombre de la parada del estado (para «Mi estado»); en Viajando, ninguna.
  String? get stopName => state == 'viajando' || stopId == null ? null : route[stopIndex!].name;

  int? _indexOf(String? id) {
    if (id == null) return null;
    final i = route.indexWhere((s) => s.id == id);
    return i < 0 ? null : i;
  }

  /// Estado declarado a mano por el trabajador o recibido del servidor (con
  /// su parada, si la hay).
  void declare(String newState, {String? stopId, DateTime? at}) {
    newState = normalize(newState)!;
    state = newState;
    stopIndex = _indexOf(stopId) ?? (newState == 'no_voy' ? null : stopIndex);
    slowCount = 0;
    if (newState == 'viajando') boardIndex ??= stopIndex;
    if (newState == 'no_voy' || newState == 'dejado') finished = true;
    if (newState == 'no_recogido' || newState == 'retrasado') waitingSince = at ?? lastTime ?? DateTime.now();
  }

  /// La parada más cercana a [p] entre las que el vehículo no ha pasado.
  int? _nearestPending(GeoPoint p, Set<int> passed) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < route.length; i++) {
      if (passed.contains(i)) continue;
      final d = distanceMeters(p, route[i].point);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  int _nearest(GeoPoint p) {
    var best = 0;
    for (var i = 1; i < route.length; i++) {
      if (distanceMeters(p, route[i].point) < distanceMeters(p, route[best].point)) best = i;
    }
    return best;
  }

  TrackerStep step(GeoPoint point, DateTime now, TripInfo trip) {
    if (finished) return const TrackerStep(finished: true);
    if (trip.closed) {
      finished = true;
      return const TrackerStep(finished: true);
    }

    final previousPoint = lastPoint;
    final previousTime = lastTime;
    lastPoint = point;
    lastTime = now;
    final passed = trip.passed;

    // Primer cálculo: solo la posición.
    if (previousPoint == null || previousTime == null) {
      if (state != null && state != 'de_camino') return const TrackerStep();
      final target = _nearestPending(point, passed);
      if (target == null) return const TrackerStep();
      final inside = distanceMeters(point, route[target].point) <= config.stopRadius;
      return _change(inside ? 'en_parada' : 'de_camino', target);
    }

    final seconds = max(1, now.difference(previousTime).inMilliseconds / 1000);
    final moved = distanceMeters(previousPoint, point);
    final speed = moved / seconds;

    if (isSensor) return _sensorStep(point, speed, moved, trip);

    // Alejándose a velocidad de vehículo de la parada [i]: subió.
    bool leavesFast(int i) {
      final d1 = distanceMeters(previousPoint, route[i].point);
      final d2 = distanceMeters(point, route[i].point);
      return d2 > config.stopRadius && d2 - d1 > config.gpsTolerance && (d2 - d1) / seconds > config.humanSpeed;
    }

    // No recogido o Retrasado (finales): solo un No recogido que sí subió pasa a Viajando.
    if (state == 'no_recogido' || state == 'retrasado') {
      if (state == 'no_recogido' && stopIndex != null && leavesFast(stopIndex!)) return _board(stopIndex!);
      if (waitingSince != null && now.difference(waitingSince!) >= config.finalWait) {
        finished = true;
        return const TrackerStep(finished: true);
      }
      return const TrackerStep();
    }

    // En la parada: sube (Viajando) o el vehículo pasó sin recogerle (No recogido).
    if (state == 'en_parada' && stopIndex != null) {
      final s = stopIndex!;
      if (leavesFast(s)) return _board(s);
      if (passed.contains(s)) {
        waitingSince = now;
        return _change('no_recogido', s);
      }
      if (distanceMeters(point, route[s].point) <= config.stopRadius) return const TrackerStep();
    }

    // De camino: el vehículo pasó por su parada antes de que llegara (Retrasado).
    if (state == 'de_camino' && stopIndex != null && passed.contains(stopIndex)) {
      waitingSince = now;
      return _change('retrasado', stopIndex);
    }

    final target = _nearestPending(point, passed);
    if (target == null) {
      // El vehículo ya pasó por todas: no hay a dónde ir.
      finished = true;
      return const TrackerStep(finished: true);
    }
    final d2 = distanceMeters(point, route[target].point);
    if (d2 <= config.stopRadius) return _change('en_parada', target);

    final d1 = distanceMeters(previousPoint, route[target].point);
    if (d2 < d1 - config.gpsTolerance || state == null) return _change('de_camino', target);
    if (d2 > d1 + config.gpsTolerance && d2 > config.abandonDistance) {
      // Se aleja de todas las paradas más allá de la Distancia abandono: No voy (final).
      finished = true;
      return _change('no_voy', null, finished: true);
    }
    // Quieto (o alejándose todavía cerca): conserva el estado; De camino sigue hacia la más cercana.
    if (state == 'de_camino' && target != stopIndex) return _change('de_camino', target);
    if (state == 'en_parada') return _change('de_camino', target);
    return const TrackerStep();
  }

  TrackerStep _board(int index) {
    boardIndex = index;
    sensorNext = max(sensorNext, index + 1);
    enteredNext = false;
    prevNextDistance = null;
    prevAfterNextDistance = null;
    return _change('viajando', index);
  }

  TrackerStep _change(String next, int? index, {bool finished = false}) {
    if (next == state && index == stopIndex) return TrackerStep(finished: finished);
    state = next;
    stopIndex = index;
    slowCount = 0;
    return TrackerStep(newState: next, stopId: stopId, finished: finished);
  }

  /// Sensor del vehículo y Dejado.
  TrackerStep _sensorStep(GeoPoint point, double speed, double moved, TripInfo trip) {
    final vehicleState = moved > config.gpsTolerance ? 'en_movimiento' : 'detenido';
    sensorNext = max(sensorNext, trip.nextStopIndex);

    // Avance de la próxima parada: entró en su radio y salió alejándose; o la
    // saltó (se aleja de ella y se acerca a la siguiente).
    if (sensorNext < route.length) {
      final dn = distanceMeters(point, route[sensorNext].point);
      final dn1 = sensorNext + 1 < route.length ? distanceMeters(point, route[sensorNext + 1].point) : null;
      if (dn <= config.stopRadius) {
        enteredNext = true;
      } else if (enteredNext) {
        sensorNext++;
        enteredNext = false;
      } else if (prevNextDistance != null &&
          dn > prevNextDistance! + config.gpsTolerance &&
          dn1 != null &&
          prevAfterNextDistance != null &&
          dn1 < prevAfterNextDistance! - config.gpsTolerance) {
        sensorNext++;
      }
      prevNextDistance = sensorNext < route.length ? distanceMeters(point, route[sensorNext].point) : null;
      prevAfterNextDistance = sensorNext + 1 < route.length ? distanceMeters(point, route[sensorNext + 1].point) : null;
    }
    final atStop = vehicleState == 'detenido' && sensorNext < route.length && distanceMeters(point, route[sensorNext].point) <= config.stopRadius;

    // Dejado: a velocidad humana «Cálculos consecutivos» veces, en el radio de
    // una parada o mientras los demás sensores dicen que el vehículo sigue.
    slowCount = speed <= config.humanSpeed ? slowCount + 1 : 0;
    String? newState;
    String? droppedAt;
    var done = false;
    if (slowCount >= config.consecutive) {
      final nearest = _nearest(point);
      final inStop = distanceMeters(point, route[nearest].point) <= config.stopRadius;
      final vehicleGoesOn = trip.vehicleState == 'en_movimiento' && trip.sensors > 1;
      if (inStop || vehicleGoesOn) {
        state = 'dejado';
        stopIndex = nearest;
        newState = 'dejado';
        droppedAt = route[nearest].id;
        finished = true;
        done = true;
      }
    }
    return TrackerStep(newState: newState, stopId: droppedAt, vehicleState: vehicleState, nextStopIndex: sensorNext, atStop: atStop, finished: done);
  }

  Map<String, dynamic> toJson() => {
        'version': 44,
        'outbound': outbound,
        'route': [for (final s in route) s.toJson()],
        'config': config.toJson(),
        'state': state,
        'stopIndex': stopIndex,
        'finished': finished,
        'lastPoint': lastPoint?.toJson(),
        'lastTime': lastTime?.toIso8601String(),
        'slowCount': slowCount,
        'waitingSince': waitingSince?.toIso8601String(),
        'boardIndex': boardIndex,
        'sensorNext': sensorNext,
        'enteredNext': enteredNext,
        'prevNextDistance': prevNextDistance,
        'prevAfterNextDistance': prevAfterNextDistance,
      };

  factory WorkerTracker.fromJson(Map<String, dynamic> j) {
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return WorkerTracker(
      outbound: j['outbound'] == true,
      route: [for (final s in j['route'] as List) RouteStop.fromJson(Map<String, dynamic>.from(s as Map))],
      config: TrackerConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
    )
      ..state = normalize(j['state'] as String?)
      ..stopIndex = (j['stopIndex'] as num?)?.toInt()
      ..finished = j['finished'] == true
      ..lastPoint = j['lastPoint'] == null ? null : GeoPoint.fromJson(Map<String, dynamic>.from(j['lastPoint'] as Map))
      ..lastTime = date(j['lastTime'])
      ..slowCount = (j['slowCount'] as num?)?.toInt() ?? 0
      ..waitingSince = date(j['waitingSince'])
      ..boardIndex = (j['boardIndex'] as num?)?.toInt()
      ..sensorNext = (j['sensorNext'] as num?)?.toInt() ?? 1
      ..enteredNext = j['enteredNext'] == true
      ..prevNextDistance = (j['prevNextDistance'] as num?)?.toDouble()
      ..prevAfterNextDistance = (j['prevAfterNextDistance'] as num?)?.toDouble();
  }
}
