import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../models/models.dart';
import '../../services/app_pin.dart';
import '../../services/app_updates.dart';
import '../../services/user_settings.dart';
import '../../services/session.dart';
import '../widgets/common.dart';
import '../updates/update_screen.dart';
import 'global_settings_screen.dart';
import 'setting_editor.dart';

/// Ajustes del usuario agrupados como en docs/05-app.md §5.4, más la
/// seguridad del teléfono y el servidor.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

const _groups = <String, List<String>>{
  'Aviso de salida': ['departure_notice_mode', 'departure_notice_minutes_before', 'departure_notice_fixed_time', 'departure_notice_fixed_days_before', 'departure_notice_fallback', 'departure_notice_template'],
  'Aviso de regreso': ['return_notice_mode', 'return_notice_minutes_before', 'return_notice_fixed_time', 'return_notice_fixed_days_before', 'return_notice_fallback', 'return_notice_template'],
  'Paso por paradas': ['stop_notice_scope', 'stop_notice_after_boarding', 'stop_notice_template'],
  'Cambios y cancelaciones': ['change_notice_template', 'cancel_notice_template', 'notify_during_absence'],
  'Recorrido': ['trip_view', 'tts_enabled', 'share_location', 'location_interval_seconds'],
  'Frecuencias': [
    'background_sync_enabled', 'trips_poll_foreground_seconds', 'trips_poll_background_minutes', 'tracking_poll_foreground_seconds',
    'tracking_poll_background_seconds', 'trip_chat_poll_foreground_seconds', 'trip_chat_poll_background_minutes',
    'conversations_poll_foreground_seconds', 'conversations_poll_background_minutes', 'notices_poll_foreground_seconds', 'notices_poll_background_minutes',
  ],
};

class _SettingsScreenState extends State<SettingsScreen> {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, UserSettings)>>();
  bool _pin = false;
  bool _rememberLogin = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    AppPin.isEnabled().then((v) => setState(() => _pin = v));
    Storage.getBool(Session.rememberLoginKey, fallback: true).then((v) => setState(() => _rememberLogin = v));
    AppUpdates.currentVersionName().then((v) => setState(() => _version = v));
  }

  Future<(Map<String, SettingDefinition>, UserSettings)> _load() async {
    final api = context.api;
    return (await loadSettingDefinitions(api), await UserSettings.refresh(api));
  }

  Future<void> _edit(SettingDefinition definition, String current) async {
    final value = await editSettingValue(context, definition, current);
    if (value == null || !mounted) return;
    final ok = await runAction(context, () => UserSettings.save(context.api, definition.key, value));
    if (ok && mounted) {
      await context.session.reloadSettings();
      _view.currentState?.reload();
    }
  }

  Future<void> _reset(SettingDefinition definition) async {
    await runAction(context, () => UserSettings.reset(context.api, definition.key), success: 'Se usa el valor general');
    if (mounted) {
      await context.session.reloadSettings();
      _view.currentState?.reload();
    }
  }

  /// Activar o cambiar el PIN de la app (se pide dos veces).
  Future<void> _setPin() async {
    final pin = await promptText(context, 'PIN nuevo (${AppPin.minLength} a ${AppPin.maxLength} dígitos)', required: true);
    if (pin == null || !mounted) return;
    if (!AppPin.isValidFormat(pin)) {
      showMessage(context, 'El PIN debe tener entre ${AppPin.minLength} y ${AppPin.maxLength} dígitos.');
      return;
    }
    final repeated = await promptText(context, 'Repite el PIN', required: true);
    if (repeated == null || !mounted) return;
    if (repeated != pin) {
      showMessage(context, 'Los PIN no coinciden.');
      return;
    }
    await AppPin.set(pin);
    setState(() => _pin = true);
    if (mounted) showMessage(context, 'Se pedirá el PIN al abrir la app.');
  }

  Future<void> _removePin() async {
    await AppPin.remove();
    setState(() => _pin = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.me;
    final operator = me.roles.isDriver || me.roles.isItineraryChief || me.managesTransport;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: AsyncView<(Map<String, SettingDefinition>, UserSettings)>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final (definitions, settings) = data;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const SectionTitle('Seguridad (solo en este teléfono)'),
            SwitchListTile(
              title: const Text('Pedir un PIN al abrir la app'),
              subtitle: const Text('Un PIN propio de MiTransporte, distinto del bloqueo del teléfono'),
              value: _pin,
              onChanged: (value) => value ? _setPin() : _removePin(),
            ),
            if (_pin) ListTile(leading: const Icon(Icons.pin_outlined), title: const Text('Cambiar el PIN'), onTap: _setPin),
            SwitchListTile(
              title: const Text('Recordar mi usuario'),
              subtitle: const Text('Aparece ya escrito al iniciar sesión'),
              value: _rememberLogin,
              onChanged: (value) async {
                await Storage.setBool(Session.rememberLoginKey, value);
                if (!value) await Storage.saveLastLogin(null);
                setState(() => _rememberLogin = value);
              },
            ),
            for (final group in _groups.entries) ...[
              SectionTitle(group.key),
              for (final key in group.value)
                if (definitions[key] != null && (key != 'tts_enabled' || operator))
                  ListTile(
                    title: Text(definitions[key]!.name),
                    subtitle: Text(describeSetting(definitions[key]!, settings.string(key))),
                    trailing: definitions[key]!.valueType == 'boolean'
                        ? Switch(value: settings.string(key) == '1', onChanged: (_) => _edit(definitions[key]!, settings.string(key)))
                        : const Icon(Icons.chevron_right),
                    onTap: () => _edit(definitions[key]!, settings.string(key)),
                    onLongPress: () => _reset(definitions[key]!),
                  ),
            ],
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Mantén pulsado un ajuste para volver a su valor general.'),
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Buscar actualizaciones'),
              subtitle: Text('Versión instalada: $_version'),
              onTap: () async {
                try {
                  final update = await AppUpdates.check(context.api);
                  if (!context.mounted) return;
                  if (update == null) {
                    showMessage(context, 'Tienes la última versión.');
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateScreen(update: update)));
                  }
                } catch (error) {
                  if (context.mounted) showError(context, error);
                }
              },
            ),
            if (me.managesTransport) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Ajustes generales'),
                subtitle: const Text('Valores para todos los usuarios'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalSettingsScreen())),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
