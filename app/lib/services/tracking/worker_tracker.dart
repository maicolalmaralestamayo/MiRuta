/// Estado del trabajador y del vehículo calculados EN EL TELÉFONO (docs/11
/// §11.43 y §11.44). Código puro, sin plugins: se prueba en test/.
///
/// En cada cálculo («Frecuencia cálculo») llega la posición del teléfono. Con
/// la distancia a la parada de referencia en el cálculo anterior (d1) y en el
/// actual (d2):
///
/// 1. d2 ≤ Radio parada → En la parada.
/// 2. |d1 − d2| ≤ Tolerancia GPS → conserva el estado.
/// 3. Se acerca (d2 < d1) → De camino a la parada.
/// 4. Se aleja: si antes estuvo En la parada y la velocidad supera la
///    Velocidad humana → Viajando (ida) / Recogido (regreso); si no → No voy a
///    viajar (definitivo a más de Distancia abandono).
///
/// Ida: la parada de referencia es la primera. Viajando es semidefinitivo:
/// solo pasa a Dejado tras «Cálculos consecutivos» a velocidad humana dentro
/// del radio de alguna parada del recorrido.
///
/// Regreso: la referencia es su parada. Cuando el vehículo pasó por ella: si
/// estaba En la parada y no sale a velocidad de vehículo → Botado; si llega
/// después → Dormido. Tras «Espera final» deja de calcular.
///
/// Viajando (ida) y Recogido (regreso) convierten el teléfono en sensor del
/// vehículo: Detenido / En movimiento (umbral: Tolerancia GPS), próxima parada
/// y si está detenido en su radio.
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

/// Lo que se sabe del viaje por el servidor (respuesta del último informe).
class TripInfo {
  final String status;

  /// Regreso: el vehículo ya pasó por la parada del trabajador.
  final bool vehiclePassedMyStop;

  /// Próxima parada según el servidor (0 = salida).
  final int nextStopIndex;

  const TripInfo({required this.status, this.vehiclePassedMyStop = false, this.nextStopIndex = 0});
}

/// Resultado de un cálculo.
class TrackerStep {
  /// Estado nuevo del trabajador (null si no cambió).
  final String? newState;

  /// Con Dejado: la parada donde se bajó.
  final String? stopId;

  /// Datos del sensor (solo si es sensor).
  final String? vehicleState;
  final int? nextStopIndex;
  final bool? atStop;

  /// Deja de calcular (estado definitivo, espera final o viaje cerrado).
  final bool finished;

  const TrackerStep({this.newState, this.stopId, this.vehicleState, this.nextStopIndex, this.atStop, this.finished = false});

  bool get isSensor => vehicleState != null;
}

/// Máquina de estados del trabajador en un viaje.
class WorkerTracker {
  final bool outbound;
  final List<RouteStop> route;

  /// Índice de su parada en [route] (el regreso va de la última a la primera).
  final int myIndex;
  final TrackerConfig config;

  // Estado (se guarda entre cálculos con toJson/fromJson).
  String? state;
  bool definitive = false;
  bool finished = false;
  bool reachedStop = false;
  double? lastDistance;
  GeoPoint? lastPoint;
  DateTime? lastTime;
  int slowCount = 0;
  DateTime? waitingSince;
  DateTime? passedAt;

  // Sensor
  int sensorNext = 1;
  bool enteredNext = false;
  double? prevNextDistance;
  double? prevAfterNextDistance;

  WorkerTracker({required this.outbound, required this.route, required this.myIndex, this.config = const TrackerConfig()});

  static const finalStates = {'dejado', 'recogido'};

  GeoPoint get reference => outbound ? route.first.point : route[myIndex].point;

  bool get isSensor => outbound ? state == 'viajando' : state == 'recogido';

  /// Estado declarado a mano por el trabajador (o recibido del servidor).
  void declare(String newState) {
    state = newState;
    if (newState == 'en_parada') reachedStop = true;
    slowCount = 0;
    if (newState == 'no_voy' || newState == 'dejado') {
      definitive = true;
      finished = true;
    }
    if (newState == 'botado' || newState == 'dormido') waitingSince = lastTime ?? DateTime.now();
  }

  TrackerStep step(GeoPoint point, DateTime now, TripInfo trip) {
    if (finished) return const TrackerStep(finished: true);
    if (trip.status == 'terminado' || trip.status == 'cancelado') {
      finished = true;
      return const TrackerStep(finished: true);
    }

    final d2 = distanceMeters(point, reference);
    final previousPoint = lastPoint;
    final previousTime = lastTime;
    final d1 = lastDistance;
    lastPoint = point;
    lastTime = now;
    lastDistance = d2;

    // Primer cálculo: solo la distancia.
    if (previousPoint == null || previousTime == null || d1 == null) {
      final initial = d2 <= config.stopRadius ? 'en_parada' : 'de_camino';
      if (initial == 'en_parada') reachedStop = true;
      if (state == null || (state == 'de_camino' && initial == 'en_parada')) return _change(initial);
      return const TrackerStep();
    }

    final seconds = max(1, now.difference(previousTime).inMilliseconds / 1000);
    final moved = distanceMeters(previousPoint, point);
    final speed = moved / seconds;

    if (isSensor) return _sensorStep(point, speed, moved, trip);

    // Botado / Dormido: si se aleja, No voy; pasada la espera final, deja de calcular.
    if (state == 'botado' || state == 'dormido') {
      if (d2 > config.stopRadius && d2 - d1 > config.gpsTolerance) {
        definitive = true;
        finished = true;
        return _change('no_voy', finished: true);
      }
      if (waitingSince != null && now.difference(waitingSince!) >= config.finalWait) {
        finished = true;
        return const TrackerStep(finished: true);
      }
      return const TrackerStep();
    }

    // Regreso: el vehículo ya pasó por su parada.
    if (!outbound && trip.vehiclePassedMyStop) {
      passedAt ??= now;
      if (state == 'en_parada') {
        if (d2 > config.stopRadius && d2 - d1 > config.gpsTolerance && (d2 - d1) / seconds > config.humanSpeed) {
          return _change('recogido');
        }
        slowCount = speed <= config.humanSpeed ? slowCount + 1 : 0;
        if (slowCount >= config.consecutive) {
          waitingSince = now;
          return _change('botado');
        }
        return const TrackerStep();
      }
      if (d2 <= config.stopRadius) {
        waitingSince = now;
        return _change('dormido');
      }
      if (now.difference(passedAt!) >= config.finalWait || (d2 > config.abandonDistance && d2 - d1 > config.gpsTolerance)) {
        definitive = true;
        finished = true;
        return _change('no_voy', finished: true);
      }
    }

    // Ida en ejecución: quien no está en el vehículo ni en la parada de salida no va.
    if (outbound && trip.status == 'en_ejecucion' && state != 'en_parada') {
      definitive = true;
      finished = true;
      return _change('no_voy', finished: true);
    }

    String next;
    if (d2 <= config.stopRadius) {
      next = 'en_parada';
      reachedStop = true;
    } else if ((d1 - d2).abs() <= config.gpsTolerance) {
      next = state ?? 'de_camino';
    } else if (d2 < d1) {
      next = 'de_camino';
    } else if (reachedStop && (d2 - d1) / seconds > config.humanSpeed) {
      next = outbound ? 'viajando' : 'recogido';
    } else {
      next = 'no_voy';
      if (d2 > config.abandonDistance || (outbound && trip.status == 'en_ejecucion')) {
        definitive = true;
        finished = true;
        return _change('no_voy', finished: true);
      }
    }
    return _change(next);
  }

  TrackerStep _change(String next, {bool finished = false}) {
    if (next == state) return TrackerStep(finished: finished);
    state = next;
    slowCount = 0;
    if (isSensor) {
      sensorNext = max(sensorNext, 1);
      enteredNext = false;
      prevNextDistance = null;
      prevAfterNextDistance = null;
    }
    return TrackerStep(newState: next, finished: finished);
  }

  /// Sensor del vehículo y, en la ida, Dejado.
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

    String? newState;
    String? droppedAt;
    var done = false;
    if (outbound) {
      // Dejado: velocidad humana en N cálculos seguidos dentro del radio de alguna parada.
      RouteStop? near;
      for (final stop in route) {
        if (distanceMeters(point, stop.point) <= config.stopRadius) {
          near = stop;
          break;
        }
      }
      slowCount = speed <= config.humanSpeed && near != null ? slowCount + 1 : 0;
      if (slowCount >= config.consecutive && near != null) {
        state = 'dejado';
        newState = 'dejado';
        droppedAt = near.id;
        definitive = true;
        finished = true;
        done = true;
      }
    }
    return TrackerStep(newState: newState, stopId: droppedAt, vehicleState: vehicleState, nextStopIndex: sensorNext, atStop: atStop, finished: done);
  }

  Map<String, dynamic> toJson() => {
        'outbound': outbound,
        'route': [for (final s in route) s.toJson()],
        'myIndex': myIndex,
        'config': config.toJson(),
        'state': state,
        'definitive': definitive,
        'finished': finished,
        'reachedStop': reachedStop,
        'lastDistance': lastDistance,
        'lastPoint': lastPoint?.toJson(),
        'lastTime': lastTime?.toIso8601String(),
        'slowCount': slowCount,
        'waitingSince': waitingSince?.toIso8601String(),
        'passedAt': passedAt?.toIso8601String(),
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
      myIndex: (j['myIndex'] as num).toInt(),
      config: TrackerConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
    )
      ..state = j['state'] as String?
      ..definitive = j['definitive'] == true
      ..finished = j['finished'] == true
      ..reachedStop = j['reachedStop'] == true
      ..lastDistance = (j['lastDistance'] as num?)?.toDouble()
      ..lastPoint = j['lastPoint'] == null ? null : GeoPoint.fromJson(Map<String, dynamic>.from(j['lastPoint'] as Map))
      ..lastTime = date(j['lastTime'])
      ..slowCount = (j['slowCount'] as num?)?.toInt() ?? 0
      ..waitingSince = date(j['waitingSince'])
      ..passedAt = date(j['passedAt'])
      ..sensorNext = (j['sensorNext'] as num?)?.toInt() ?? 1
      ..enteredNext = j['enteredNext'] == true
      ..prevNextDistance = (j['prevNextDistance'] as num?)?.toDouble()
      ..prevAfterNextDistance = (j['prevAfterNextDistance'] as num?)?.toDouble();
  }
}
