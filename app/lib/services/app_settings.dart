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
    'minimo_confirmaciones': '3',
    'velocidad_humana': '10km/hor',
    'tolerancia_gps': '20m',
    'distancia_abandono': '1km',
    'frecuencia_calculo': '10seg',
    'calculos_consecutivos': '6',
    'espera_final': '10min',
    'plazo_eliminacion': '5hor',
    'duracion_maxima': '5hor',
    'espera_cierre': '2hor',
    'detencion_larga': '5min',
    'frecuencia_reposo': '1hor',
    'frecuencia_dia_viaje': '15min',
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
