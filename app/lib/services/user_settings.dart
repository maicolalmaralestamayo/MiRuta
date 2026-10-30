import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/models.dart';

/// Ajustes del usuario (valor efectivo de cada uno). Se guardan en el
/// teléfono para que las tareas en segundo plano los usen sin conexión.
class UserSettings {
  static const _key = 'user.settings';

  final Map<String, String> values;

  UserSettings(this.values);

  static Future<UserSettings> cached() async {
    final json = await Storage.getJson(_key);
    return UserSettings(json.map((key, value) => MapEntry(key, value.toString())));
  }

  /// Descarga los ajustes efectivos del usuario y los guarda.
  static Future<UserSettings> refresh(ApiClient api) async {
    final document = await api.get('/me/settings');
    final values = {for (final r in document.resources) r.id: r.string('value') ?? ''};
    await Storage.setJson(_key, values);
    return UserSettings(values);
  }

  /// Cambia un ajuste propio y devuelve el valor efectivo guardado.
  static Future<String> save(ApiClient api, String key, Object value) async {
    final document = await api.patch('/me/settings/$key', {
      'data': {'type': 'user-settings', 'id': key, 'attributes': {'value': value}},
    });
    final saved = document.resource.string('value') ?? '';
    final json = await Storage.getJson(_key);
    json[key] = saved;
    await Storage.setJson(_key, json);
    return saved;
  }

  static Future<void> reset(ApiClient api, String key) async {
    await api.delete('/me/settings/$key');
    await refresh(api);
  }

  String string(String key, [String fallback = '']) => values[key] ?? fallback;

  int integer(String key, int fallback) => int.tryParse(values[key] ?? '') ?? fallback;

  bool boolean(String key, bool fallback) => values.containsKey(key) ? values[key] == '1' : fallback;
}

/// Definiciones de los ajustes (para pantallas de configuración).
Future<Map<String, SettingDefinition>> loadSettingDefinitions(ApiClient api) async {
  final document = await api.get('/setting-definitions');
  return {for (final r in document.resources) r.id: SettingDefinition.from(r)};
}
