import 'storage.dart';

/// Reloj y zona horaria del servidor (docs/11 §11.67, la hora de diferencia
/// de la captura 02 de la 4.5.0).
///
/// - Las horas se **muestran en la zona del servidor** (America/Havana), la
///   que llevan sus fechas (p. ej. «…T12:05:00-05:00»), aunque el teléfono
///   tenga otra zona o la hora puesta a mano: antes se pasaban a la zona del
///   teléfono y, con una zona distinta, salía una hora de diferencia.
/// - La **hora de captura** que envía el teléfono va en UTC (con «Z») y
///   corregida con la diferencia entre el reloj del teléfono y el del
///   servidor: antes iba sin zona y el servidor la leía como hora de La Habana.
class ServerClock {
  static const _offsetKey = 'server.utc_offset_minutes';
  static const _skewKey = 'server.clock_skew_ms';

  static Duration? _offset;
  static Duration _skew = Duration.zero;

  /// Zona del servidor (diferencia con UTC); sin datos, la del teléfono.
  static Duration get offset => _offset ?? DateTime.now().timeZoneOffset;

  /// Hora del servidor menos hora del teléfono.
  static Duration get skew => _skew;

  /// Diferencia con UTC de una fecha ISO 8601 («-05:00», «+01:00», «Z»), o null.
  static Duration? offsetOf(String? iso) {
    if (iso == null) return null;
    final text = iso.trim();
    if (text.endsWith('Z')) return Duration.zero;
    final match = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(text);
    if (match == null || !text.contains('T')) return null;
    final minutes = int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
    return Duration(minutes: match.group(1) == '-' ? -minutes : minutes);
  }

  /// Aprende la zona y el reloj del servidor de su «serverTime».
  static Future<void> learn(String? serverTime, {DateTime? receivedAt, bool save = true}) async {
    final offset = offsetOf(serverTime);
    final server = serverTime == null ? null : DateTime.tryParse(serverTime);
    if (offset == null || server == null) return;
    _offset = offset;
    _skew = server.difference(receivedAt ?? DateTime.now());
    // Diferencias de menos de 2 s son la demora de la red.
    if (_skew.abs() < const Duration(seconds: 2)) _skew = Duration.zero;
    if (save) {
      await Storage.setInt(_offsetKey, offset.inMinutes);
      await Storage.setInt(_skewKey, _skew.inMilliseconds);
    }
  }

  /// Lo guardado (al arrancar la app o el servicio de la ventana de viaje).
  static Future<void> load() async {
    final minutes = await Storage.getInt(_offsetKey);
    if (minutes != null) _offset = Duration(minutes: minutes);
    _skew = Duration(milliseconds: await Storage.getInt(_skewKey) ?? 0);
  }

  /// Pruebas.
  static void set({Duration? offset, Duration skew = Duration.zero}) {
    _offset = offset;
    _skew = skew;
  }

  /// Ahora según el servidor.
  static DateTime now() => DateTime.now().add(_skew);

  /// Hora de captura para el servidor: UTC con «Z», corregida con el reloj del servidor.
  static String stamp(DateTime at) => at.add(_skew).toUtc().toIso8601String();

  /// La hora de pared en la zona del servidor de un instante (sus campos
  /// year…minute son los que se muestran; isUtc = true). Si el teléfono está
  /// ahora en la misma zona que el servidor, se usan sus reglas (con los
  /// cambios de horario de cada fecha); si no (zona mal puesta), la del servidor.
  static DateTime wall(DateTime instant) {
    final offset = _offset;
    if (offset == null || offset == DateTime.now().timeZoneOffset) {
      final l = instant.toLocal();
      return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second, l.millisecond);
    }
    return instant.toUtc().add(offset);
  }
}
