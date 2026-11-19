/// Estado del trabajador y del vehículo calculados EN EL TELÉFONO (docs/11
/// §11.43, §11.65 y §11.67). Código puro, sin plugins: se prueba en test/.
///
/// Estados del trabajador, versión definitiva (docs/11 §11.67), iguales en la
/// ida y en el regreso; se sube y se baja en cualquier parada (detectada por
/// cercanía). Distancias configurables: «Radio acercamiento» (300 m) y «Radio
/// parada» (100 m).
///
/// - **Fuera de itinerario**: a más del Radio acercamiento de todas las paradas.
/// - **Acercándose a Parada**: entre los dos radios de una parada, a velocidad
///   humana, y la distancia tiende a disminuir («Cálculos consecutivos»).
/// - **Alejándose de Parada**: igual, pero la distancia tiende a aumentar.
/// - **En Parada**: a Radio parada o menos de una parada (En espera).
/// - **Llegada tarde**: su parada dejó de estar En espera antes de que llegara
///   a ella (o llega a una que ya no lo está).
/// - **No recogido**: su parada dejó de estar En espera, el vehículo la dejó
///   atrás y él siguió En Parada.
/// - **Viajando**: estaba En Parada (o No recogido) y se aleja de la parada de
///   forma consecutiva a velocidad superior a la humana, si la parada está
///   Recogida, si es la primera parada de recogida (al iniciarse el viaje) o
///   si aún no hay datos del vehículo (sin sensores nadie podría ser el primero).
/// - **Dejado**: estaba Viajando y pasa a velocidad humana mientras la
///   distancia a la parada más cercana tiende a aumentar; queda Dejado en ella.
/// - **No viajaré**: solo a mano; nunca se calcula.
///
/// Todos se pueden poner a mano (docs/11 §11.67): el estado manual se respeta
/// hasta que el cálculo detecta un cambio real (la posición pasa a otra
/// clasificación que la que tenía al marcarlo, o un suceso: el vehículo se
/// lleva o deja atrás al trabajador).
///
/// Viajando convierte el teléfono en sensor del vehículo: Detenido / En
/// movimiento (umbral: Tolerancia GPS), velocidad, próxima parada, si está
/// dentro de su radio y si está detenido en él.
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

/// Ajustes del cálculo (grupos «Generales» y «Estado trabajador»).
class TrackerConfig {
  final double stopRadius;
  final double approachRadius;
  final double gpsTolerance;

  /// Metros por segundo.
  final double humanSpeed;
  final int consecutive;

  const TrackerConfig({
    this.stopRadius = 100,
    this.approachRadius = 300,
    this.gpsTolerance = 20,
    this.humanSpeed = 10000 / 3600,
    this.consecutive = 3,
  });

  Map<String, dynamic> toJson() => {
        'stopRadius': stopRadius,
        'approachRadius': approachRadius,
        'gpsTolerance': gpsTolerance,
        'humanSpeed': humanSpeed,
        'consecutive': consecutive,
      };

  factory TrackerConfig.fromJson(Map<String, dynamic> j) => TrackerConfig(
        stopRadius: (j['stopRadius'] as num?)?.toDouble() ?? 100,
        approachRadius: (j['approachRadius'] as num?)?.toDouble() ?? 300,
        gpsTolerance: (j['gpsTolerance'] as num?)?.toDouble() ?? 20,
        humanSpeed: (j['humanSpeed'] as num?)?.toDouble() ?? 10000 / 3600,
        consecutive: (j['consecutive'] as num?)?.toInt() ?? 3,
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

/// Estados de una parada (docs/11 §11.67).
const stopWaiting = 'en_espera';
const stopPickedUp = 'recogida';

/// Lo que se sabe del viaje por el servidor (respuesta del último envío).
class TripInfo {
  final String status;

  /// Estado de cada parada distinto de En espera (posición → estado).
  final Map<int, String> stopStates;

  /// Paradas que el vehículo ya dejó atrás.
  final Set<int> left;

  /// Próxima parada según el servidor (0 = salida).
  final int nextStopIndex;

  /// Estado del vehículo por mayoría de los sensores (null = sin datos).
  final String? vehicleState;

  /// El vehículo está detenido en la próxima parada.
  final bool vehicleAtStop;

  /// Sensores activos.
  final int sensors;

  const TripInfo({
    required this.status,
    this.stopStates = const {},
    this.left = const {},
    this.nextStopIndex = 0,
    this.vehicleState,
    this.vehicleAtStop = false,
    this.sensors = 0,
  });

  bool get closed => status == 'terminado' || status == 'cancelado';

  bool get running => status == 'en_ejecucion';

  String stopState(int i) => stopStates[i] ?? stopWaiting;

  bool waiting(int i) => stopState(i) == stopWaiting;

  /// El vehículo dejó atrás la parada [i] (o la pasó: ya va hacia una posterior).
  bool leftBehind(int i) => left.contains(i) || (running && nextStopIndex > i && !waiting(i));

  /// El vehículo está detenido ahora en la parada [i].
  bool stoppedAt(int i) => running && vehicleState == 'detenido' && vehicleAtStop && nextStopIndex == i;

  /// Sin datos del vehículo (ningún sensor).
  bool get noVehicleData => vehicleState == null || sensors == 0;
}

/// Resultado de un cálculo.
class TrackerStep {
  /// Estado nuevo del trabajador (null si no cambió ni cambió su parada).
  final String? newState;

  /// La parada detectada del estado (en Dejado, donde se bajó; null sin parada).
  final String? stopId;

  /// Observación del sensor (solo si es sensor).
  final String? vehicleState;
  final int? nextStopIndex;
  final bool? atStop;
  final bool? inRadius;

  /// Velocidad del vehículo en km/h (sensor).
  final double? speedKmh;

  /// Deja de calcular (Dejado, No viajaré, viaje cerrado o nada más que esperar).
  final bool finished;

  const TrackerStep({this.newState, this.stopId, this.vehicleState, this.nextStopIndex, this.atStop, this.inRadius, this.speedKmh, this.finished = false});

  bool get isSensor => vehicleState != null;
}

/// Un punto de la posición con su hora.
class _Fix {
  final GeoPoint point;
  final DateTime time;

  const _Fix(this.point, this.time);

  Map<String, dynamic> toJson() => {...point.toJson(), 't': time.toIso8601String()};

  static _Fix? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['t']}');
    return time == null ? null : _Fix(GeoPoint.fromJson(Map<String, dynamic>.from(raw)), time);
  }
}

/// Máquina de estados del trabajador en un viaje (ida o regreso).
class WorkerTracker {
  final bool outbound;
  final List<RouteStop> route;
  final TrackerConfig config;

  static const outOfRoute = 'fuera_itinerario';
  static const approaching = 'acercandose';
  static const movingAway = 'alejandose';
  static const atStop = 'en_parada';
  static const late = 'llegada_tarde';
  static const leftBehind = 'no_recogido';
  static const travelling = 'viajando';
  static const dropped = 'dejado';
  static const notTravelling = 'no_viajare';

  static const states = [outOfRoute, approaching, movingAway, atStop, late, leftBehind, travelling, dropped, notTravelling];

  /// Fin del viaje para él (fin de su ventana de viaje).
  static const finalStates = {dropped, notTravelling};

  // Estado (se guarda entre cálculos con toJson/fromJson).
  String? state;

  /// Posición en [route] de la parada del estado (detectada por cercanía).
  int? stopIndex;
  bool finished = false;

  /// Últimas posiciones (las de «Cálculos consecutivos» + 1).
  final List<_Fix> _fixes = [];

  /// Estado puesto a mano: se respeta hasta un cambio real.
  bool manual = false;

  /// Clasificación por la posición cuando lo puso a mano («estado@parada»).
  String? manualBaseline;

  /// Parada donde subió (Viajando).
  int? boardIndex;

  // Movimiento propio (o del vehículo, desde Viajando lo da el servidor).
  /// Velocidad del último cálculo, en m/s.
  double speed = 0;

  /// Se movió más que la Tolerancia GPS en el último cálculo.
  bool moving = false;

  // Sensor
  int sensorNext = 1;
  bool enteredNext = false;
  double? prevNextDistance;
  double? prevAfterNextDistance;

  WorkerTracker({required this.outbound, required this.route, this.config = const TrackerConfig()});

  static String? normalize(String? s) => states.contains(s) ? s : null;

  bool get isSensor => state == travelling;

  GeoPoint? get lastPoint => _fixes.isEmpty ? null : _fixes.last.point;

  DateTime? get lastTime => _fixes.isEmpty ? null : _fixes.last.time;

  String? get stopId => stopIndex == null || stopIndex! < 0 || stopIndex! >= route.length ? null : route[stopIndex!].id;

  /// Nombre de la parada del estado (para «Mi estado»); en Viajando, ninguna.
  String? get stopName => state == travelling || stopId == null ? null : route[stopIndex!].name;

  /// km/h del último cálculo.
  double get speedKmh => speed * 3.6;

  int? _indexOf(String? id) {
    if (id == null) return null;
    final i = route.indexWhere((s) => s.id == id);
    return i < 0 ? null : i;
  }

  /// Estado declarado a mano por el trabajador ([manual]) o recibido del
  /// servidor (con su parada, si la hay).
  void declare(String newState, {String? stopId, DateTime? at, bool manual = false}) {
    final normalized = normalize(newState);
    if (normalized == null) return;
    state = normalized;
    stopIndex = normalized == notTravelling || normalized == outOfRoute ? null : (_indexOf(stopId) ?? stopIndex);
    this.manual = manual;
    // La clasificación de la posición se toma en el próximo cálculo.
    manualBaseline = null;
    if (normalized == travelling) {
      boardIndex ??= stopIndex;
      if (stopIndex != null) sensorNext = max(sensorNext, stopIndex! + 1);
    }
    finished = finalStates.contains(normalized);
  }

  /// Paradas a [p] ordenadas por distancia: (posición, metros).
  List<(int, double)> _byDistance(GeoPoint p) {
    final list = [for (var i = 0; i < route.length; i++) (i, distanceMeters(p, route[i].point))];
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  int _nearest(GeoPoint p) => _byDistance(p).first.$1;

  /// Las distancias a la parada [i] en las posiciones guardadas (de la más vieja a la última).
  List<double> _distances(int i) => [for (final f in _fixes) distanceMeters(f.point, route[i].point)];

  /// La distancia a la parada [i] tiende a aumentar (signo 1) o a disminuir
  /// (signo -1) en los últimos «Cálculos consecutivos»: ningún paso en contra
  /// más allá de la Tolerancia GPS y, en total, más que ella.
  bool _trend(int i, int sign) {
    final d = _distances(i);
    final n = config.consecutive;
    if (d.length < 2) return false;
    final window = d.length > n + 1 ? d.sublist(d.length - n - 1) : d;
    final total = (window.last - window.first) * sign;
    if (total <= config.gpsTolerance) return false;
    for (var k = 1; k < window.length; k++) {
      if ((window[k] - window[k - 1]) * sign < -config.gpsTolerance) return false;
    }
    return true;
  }

  /// Velocidades (m/s) de los últimos pasos (hasta «Cálculos consecutivos»).
  List<double> _speeds() {
    final result = <double>[];
    for (var k = max(1, _fixes.length - config.consecutive); k < _fixes.length; k++) {
      final seconds = max(1, _fixes[k].time.difference(_fixes[k - 1].time).inMilliseconds / 1000);
      result.add(distanceMeters(_fixes[k - 1].point, _fixes[k].point) / seconds);
    }
    return result;
  }

  /// Los últimos «Cálculos consecutivos» pasos fueron todos a velocidad de vehículo (fast) o humana.
  bool _consecutiveSpeed({required bool fast}) {
    final s = _speeds();
    if (s.length < config.consecutive) return false;
    return s.every((v) => fast ? v > config.humanSpeed : v <= config.humanSpeed);
  }

  /// Se aleja de la parada [i] de forma consecutiva a velocidad no humana.
  bool _leavesFast(int i) {
    final d = _distances(i);
    if (d.isEmpty || d.last <= config.stopRadius || !_consecutiveSpeed(fast: true)) return false;
    final n = config.consecutive;
    final window = d.length > n + 1 ? d.sublist(d.length - n - 1) : d;
    for (var k = 1; k < window.length; k++) {
      if (window[k] <= window[k - 1]) return false;
    }
    return true;
  }

  /// Clasificación por la posición (sin sucesos): Fuera de itinerario,
  /// Acercándose, Alejándose o En Parada, con su parada; null = sin cambio.
  (String, int?)? _positional(GeoPoint point, TripInfo trip, bool human) {
    final sorted = _byDistance(point);
    final inside = sorted.where((e) => e.$2 <= config.stopRadius).toList();
    if (inside.isNotEmpty) {
      // En el radio de una parada; la que sigue En espera antes que otra.
      final pending = inside.where((e) => trip.waiting(e.$1) || trip.stoppedAt(e.$1)).toList();
      if (pending.isNotEmpty) return (atStop, pending.first.$1);
      final i = inside.first.$1;
      // Llega a una parada que ya no está En espera: Llegada tarde (salvo que ya esperaba en ella).
      if (state == atStop && stopIndex == i) return (atStop, i);
      if ((state == leftBehind || state == late) && stopIndex == i) return (state!, i);
      return (late, i);
    }
    final near = sorted.where((e) => e.$2 <= config.approachRadius).toList();
    if (near.isEmpty) return (outOfRoute, null);
    // La más cercana de las que siguen En espera (si no, la más cercana).
    final target = (near.where((e) => trip.waiting(e.$1)).firstOrNull ?? near.first).$1;
    if (!human) return null;
    if (_trend(target, -1)) return (approaching, target);
    if (_trend(target, 1)) return (movingAway, target);
    // Sin tendencia: conserva Acercándose / Alejándose (con la parada más cercana).
    if (state == approaching || state == movingAway) return (state!, target);
    return state == null || state == outOfRoute ? (approaching, target) : null;
  }

  TrackerStep step(GeoPoint point, DateTime now, TripInfo trip) {
    if (trip.closed) {
      finished = true;
      return const TrackerStep(finished: true);
    }
    if (finished) return const TrackerStep(finished: true);

    final previous = _fixes.isEmpty ? null : _fixes.last;
    _fixes.add(_Fix(point, now));
    while (_fixes.length > config.consecutive + 1) {
      _fixes.removeAt(0);
    }
    if (previous != null) {
      final seconds = max(1, now.difference(previous.time).inMilliseconds / 1000);
      final moved = distanceMeters(previous.point, point);
      speed = moved / seconds;
      moving = moved > config.gpsTolerance;
    } else {
      speed = 0;
      moving = false;
    }
    final human = speed <= config.humanSpeed;

    if (isSensor) return _sensorStep(point, trip);

    // Sucesos (siempre son un cambio real, también sobre un estado manual).
    final s = stopIndex;
    if ((state == atStop || state == leftBehind) && s != null && _leavesFast(s)) {
      final first = s == 0 && trip.waiting(0) && !trip.running;
      if (first || trip.stopState(s) == stopPickedUp || trip.noVehicleData) return _board(s);
    }
    if (state == atStop && s != null && !trip.waiting(s) && trip.leftBehind(s) && !trip.stoppedAt(s)) {
      return _change(leftBehind, s);
    }
    if ((state == approaching || state == movingAway) && s != null && !trip.waiting(s) && !trip.stoppedAt(s)) {
      return _change(late, s);
    }

    // Por la posición.
    final positional = _positional(point, trip, human);
    if (manual) {
      final key = positional == null ? null : '${positional.$1}@${positional.$2}';
      if (manualBaseline == null) {
        manualBaseline = key ?? '';
        return _finishIfNothingLeft(trip);
      }
      if (key == null || key == manualBaseline) return _finishIfNothingLeft(trip);
      manual = false;
      manualBaseline = null;
    }
    if (positional != null) {
      var (next, index) = positional;
      // No recogido y Llegada tarde se conservan hasta llegar a otra parada En espera.
      final keeps = (state == leftBehind || state == late) && next != atStop;
      if (!keeps) {
        final step = _change(next, index);
        if (step.newState != null) return step;
      }
    }
    return _finishIfNothingLeft(trip);
  }

  /// Ninguna parada sigue En espera y él no viaja: ya no hay nada que esperar.
  TrackerStep _finishIfNothingLeft(TripInfo trip) {
    final nothing = trip.running && route.isNotEmpty && [for (var i = 0; i < route.length; i++) i].every((i) => !trip.waiting(i));
    if (nothing && state != travelling) {
      finished = true;
      return const TrackerStep(finished: true);
    }
    return const TrackerStep();
  }

  TrackerStep _board(int index) {
    boardIndex = index;
    manual = false;
    manualBaseline = null;
    sensorNext = max(sensorNext, index + 1);
    enteredNext = false;
    prevNextDistance = null;
    prevAfterNextDistance = null;
    return _change(travelling, index);
  }

  TrackerStep _change(String next, int? index, {bool finished = false}) {
    if (next == state && index == stopIndex) return TrackerStep(finished: finished);
    state = next;
    stopIndex = index;
    manual = false;
    manualBaseline = null;
    return TrackerStep(newState: next, stopId: stopId, finished: finished);
  }

  /// Sensor del vehículo y Dejado.
  TrackerStep _sensorStep(GeoPoint point, TripInfo trip) {
    final vehicleState = moving ? 'en_movimiento' : 'detenido';
    sensorNext = max(sensorNext, trip.nextStopIndex);

    // Avance de la próxima parada: entró en su radio y salió alejándose; o la
    // saltó (se aleja de ella y se acerca a la siguiente).
    var inRadius = false;
    if (sensorNext < route.length) {
      final dn = distanceMeters(point, route[sensorNext].point);
      final dn1 = sensorNext + 1 < route.length ? distanceMeters(point, route[sensorNext + 1].point) : null;
      if (dn <= config.stopRadius) {
        enteredNext = true;
        inRadius = true;
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
    final atStopNow = vehicleState == 'detenido' && inRadius;

    // Dejado: a velocidad humana de forma consecutiva y la distancia a la
    // parada más cercana tiende a aumentar (se aleja a pie de donde lo dejaron).
    String? newState;
    String? droppedAt;
    var done = false;
    if (_consecutiveSpeed(fast: false)) {
      final nearest = _nearest(point);
      if (_trend(nearest, 1)) {
        state = dropped;
        stopIndex = nearest;
        manual = false;
        newState = dropped;
        droppedAt = route[nearest].id;
        finished = true;
        done = true;
      }
    }
    return TrackerStep(
      newState: newState,
      stopId: droppedAt,
      vehicleState: vehicleState,
      nextStopIndex: sensorNext,
      atStop: atStopNow,
      inRadius: inRadius,
      speedKmh: double.parse(speedKmh.toStringAsFixed(1)),
      finished: done,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 50,
        'outbound': outbound,
        'route': [for (final s in route) s.toJson()],
        'config': config.toJson(),
        'state': state,
        'stopIndex': stopIndex,
        'finished': finished,
        'fixes': [for (final f in _fixes) f.toJson()],
        'manual': manual,
        'manualBaseline': manualBaseline,
        'boardIndex': boardIndex,
        'speed': speed,
        'moving': moving,
        'sensorNext': sensorNext,
        'enteredNext': enteredNext,
        'prevNextDistance': prevNextDistance,
        'prevAfterNextDistance': prevAfterNextDistance,
      };

  factory WorkerTracker.fromJson(Map<String, dynamic> j) {
    final tracker = WorkerTracker(
      outbound: j['outbound'] == true,
      route: [for (final s in j['route'] as List) RouteStop.fromJson(Map<String, dynamic>.from(s as Map))],
      config: TrackerConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
    )
      ..state = normalize(j['state'] as String?)
      ..stopIndex = (j['stopIndex'] as num?)?.toInt()
      ..finished = j['finished'] == true
      ..manual = j['manual'] == true
      ..manualBaseline = j['manualBaseline'] as String?
      ..boardIndex = (j['boardIndex'] as num?)?.toInt()
      ..speed = (j['speed'] as num?)?.toDouble() ?? 0
      ..moving = j['moving'] == true
      ..sensorNext = (j['sensorNext'] as num?)?.toInt() ?? 1
      ..enteredNext = j['enteredNext'] == true
      ..prevNextDistance = (j['prevNextDistance'] as num?)?.toDouble()
      ..prevAfterNextDistance = (j['prevAfterNextDistance'] as num?)?.toDouble();
    for (final raw in (j['fixes'] as List? ?? const [])) {
      final fix = _Fix.fromJson(raw);
      if (fix != null) tracker._fixes.add(fix);
    }
    return tracker;
  }
}
