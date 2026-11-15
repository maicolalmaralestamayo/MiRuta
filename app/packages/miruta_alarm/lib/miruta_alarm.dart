import 'package:flutter/services.dart';

/// Alarma exacta del teléfono (docs/11 §11.62): a la hora indicada, Android
/// despierta a MiRuta aunque esté cerrada y la app arranca el servicio de
/// ubicación del viaje con los datos de [schedule]. Se reprograma sola al
/// reiniciar el teléfono. Sirve en cualquier aislamiento (la app, la tarea en
/// segundo plano y el servicio del viaje).
class MirutaAlarm {
  static const _channel = MethodChannel('miruta_alarm');

  /// Programa la alarma (sustituye a la anterior). [payload]: JSON con las
  /// opciones del servicio en primer plano que se arranca.
  static Future<void> schedule(DateTime at, String payload) =>
      _channel.invokeMethod('schedule', {'at': at.millisecondsSinceEpoch, 'payload': payload});

  static Future<void> cancel() => _channel.invokeMethod('cancel');

  /// Hora programada (o null).
  static Future<DateTime?> scheduled() async {
    final at = await _channel.invokeMethod<int>('scheduled');
    return at == null || at <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  /// Android permite alarmas exactas (en Android 12 hay que concederlo).
  static Future<bool> canScheduleExact() async => await _channel.invokeMethod<bool>('canScheduleExact') ?? false;

  /// Abre el ajuste «Alarmas y recordatorios» (Android 12+).
  static Future<void> openExactAlarmSettings() => _channel.invokeMethod('openExactAlarmSettings');

  /// Fabricante del teléfono (para los avisos de «inicio automático»).
  static Future<String> manufacturer() async => (await _channel.invokeMethod<String>('manufacturer')) ?? '';

  /// Abre los ajustes de batería de la app (o los generales).
  static Future<void> openBatterySettings() => _channel.invokeMethod('openBatterySettings');
}
