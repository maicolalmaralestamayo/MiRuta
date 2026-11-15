import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:miruta_alarm/miruta_alarm.dart';

/// Estado de lo que necesita la ventana de viaje con la app cerrada (docs/11
/// §11.61 y §11.62): ubicación activada y «Permitir todo el tiempo», batería
/// sin restricciones y alarmas exactas. Sin «todo el tiempo» la app solo
/// calcula con ella abierta (y lo recuerda antes de cada viaje).
class TripPermissions {
  final bool locationOn;
  final LocationPermission permission;
  final bool batteryUnrestricted;
  final bool exactAlarms;
  final String manufacturer;

  const TripPermissions({
    this.locationOn = false,
    this.permission = LocationPermission.denied,
    this.batteryUnrestricted = false,
    this.exactAlarms = true,
    this.manufacturer = '',
  });

  /// Puede usar la ubicación con la app abierta.
  bool get foreground => locationOn && (permission == LocationPermission.always || permission == LocationPermission.whileInUse);

  /// Ubicación «Permitir todo el tiempo».
  bool get always => permission == LocationPermission.always;

  /// Todo listo para funcionar con la app cerrada.
  bool get complete => foreground && always && batteryUnrestricted && exactAlarms;

  static Future<TripPermissions> check() async {
    Future<T> safe<T>(Future<T> Function() f, T fallback) async {
      try {
        return await f();
      } catch (_) {
        return fallback;
      }
    }

    return TripPermissions(
      locationOn: await safe(Geolocator.isLocationServiceEnabled, false),
      permission: await safe(Geolocator.checkPermission, LocationPermission.denied),
      batteryUnrestricted: await safe(() => FlutterForegroundTask.isIgnoringBatteryOptimizations, true),
      exactAlarms: await safe(MirutaAlarm.canScheduleExact, true),
      manufacturer: await safe(MirutaAlarm.manufacturer, ''),
    );
  }

  /// Puede calcular con la app cerrada (ubicación todo el tiempo).
  static Future<bool> backgroundReady() async {
    final p = await check();
    return p.foreground && p.always;
  }

  /// Consejo del fabricante para que Android no cierre MiRuta.
  String get manufacturerHint => manufacturerHintFor(manufacturer);

  static String manufacturerHintFor(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'Xiaomi: en Ajustes → Aplicaciones → MiRuta active «Inicio automático» y en «Ahorro de batería» elija «Sin restricciones».';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'Huawei: en Ajustes → Batería → Inicio de aplicaciones, ponga MiRuta en «Gestionar manualmente» con todo activado.';
    }
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus') || m.contains('vivo')) {
      return 'Oppo: en Ajustes → Batería → MiRuta permita la «Actividad en segundo plano» y el «Inicio automático».';
    }
    if (m.contains('samsung')) {
      return 'Samsung: en Ajustes → Batería → Límites de uso en segundo plano, añada MiRuta a «Apps que nunca se suspenden».';
    }
    return 'Si su teléfono tiene «inicio automático» o «ahorro de batería» por aplicación, permítale a MiRuta funcionar en segundo plano.';
  }
}
