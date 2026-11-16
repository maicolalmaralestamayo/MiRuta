import 'dart:convert';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../core/units.dart';
import '../models/models.dart';

/// Ajustes de la app (un solo nivel, docs/11 §11.38 y §11.44), guardados en
/// el teléfono para usarlos sin conexión y en segundo plano.
class AppSettings {
  static const _key = 'user.settings';

  /// Valores por omisión (docs/13 §13.12), por si aún no se han descargado.
  static const defaults = {
    'radio_parada': '100m',
    'anticipacion_viaje': '10min',
    'fin_ventana': '5min',
    'minimo_confirmaciones': '3',
    'velocidad_humana': '10km/hor',
    'tolerancia_gps': '20m',
    'distancia_abandono': '1km',
    'frecuencia_corta': '10seg',
    'calculos_consecutivos': '6',
    'espera_final': '10min',
    'plazo_eliminacion': '5hor',
    'duracion_maxima': '5hor',
    'espera_cierre': '2hor',
    'detencion_larga': '5min',
    'frecuencia_larga': '15min',
    'frecuencia_chat': '5seg',
    'longitud_mensaje': '1000',
  };

  final Map<String, String> values;
  final String? version;

  const AppSettings(this.values, {this.version});

  String raw(String key) => values[key] ?? defaults[key] ?? '';

  Duration duration(String key) => parseDuration(raw(key)) ?? parseDuration(defaults[key]) ?? Duration.zero;

  double distance(String key) => parseDistance(raw(key)) ?? parseDistance(defaults[key]) ?? 0;

  double speed(String key) => parseSpeed(raw(key)) ?? parseSpeed(defaults[key]) ?? 0;

  int integer(String key) => int.tryParse(raw(key)) ?? int.tryParse(defaults[key] ?? '') ?? 0;

  /// Ventana de viaje (docs/11 §11.62): X antes de la salida.
  Duration get windowBefore => duration('anticipacion_viaje');

  /// Y después de que el viaje termine para el trabajador.
  Duration get windowAfter => duration('fin_ventana');

  /// «Frecuencia corta» (docs/11 §11.65): con la app abierta (a la vista o en
  /// recientes) y, con la app cerrada, dentro de la ventana de un viaje
  /// (mínimo 5 s). Antes «Frecuencia ventana» (frecuencia_calculo).
  Duration get shortEvery {
    final z = parseDuration(values['frecuencia_corta'] ?? values['frecuencia_calculo'] ?? '') ?? parseDuration(defaults['frecuencia_corta'])!;
    return z < const Duration(seconds: 5) ? const Duration(seconds: 5) : z;
  }

  /// «Frecuencia larga»: solo con la app cerrada y fuera de la ventana de un
  /// viaje (mínimo 15 min, límite de Android). Antes «Frecuencia fuera ventana».
  Duration get longEvery {
    final f = parseDuration(values['frecuencia_larga'] ?? values['frecuencia_reposo'] ?? '') ?? parseDuration(defaults['frecuencia_larga'])!;
    return f < const Duration(minutes: 15) ? const Duration(minutes: 15) : f;
  }

  /// Cada cuánto consulta al servidor (docs/11 §11.65): corta con la app
  /// abierta o dentro de la ventana; larga solo cerrada y fuera de ella.
  Duration every({required bool appOpen, required bool inWindow}) => appOpen || inWindow ? shortEvery : longEvery;

  Map<String, dynamic> toJson() => {'values': values, 'version': version};

  static Future<AppSettings> cached() async {
    final json = await Storage.getJson(_key);
    return AppSettings(Map<String, String>.from(json['values'] as Map? ?? const {}), version: json['version'] as String?);
  }

  /// Descarga los ajustes (GET settings) y los guarda.
  static Future<(AppSettings, List<Setting>)> refresh(ApiClient api) async {
    final document = await api.get('/settings');
    final list = document.resources.map(Setting.from).toList();
    final settings = AppSettings({for (final s in list) s.key: s.value}, version: document.meta['version']?.toString());
    await Storage.setString(_key, jsonEncode(settings.toJson()));
    return (settings, list);
  }
}
