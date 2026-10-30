import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/storage.dart';
import '../../models/models.dart';
import '../../services/user_settings.dart';
import '../../services/session.dart';
import '../widgets/common.dart';
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
  bool _biometric = false;
  bool _rememberCard = true;

  @override
  void initState() {
    super.initState();
    Storage.getBool(Session.biometricKey).then((v) => setState(() => _biometric = v));
    Storage.getBool(Session.rememberCardKey, fallback: true).then((v) => setState(() => _rememberCard = v));
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

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        if (mounted) showMessage(context, 'Este teléfono no tiene huella ni bloqueo de pantalla configurado.');
        return;
      }
      if (!await auth.authenticate(localizedReason: 'Confirma para activar el desbloqueo')) return;
    }
    await Storage.setBool(Session.biometricKey, value);
    setState(() => _biometric = value);
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
            SwitchListTile(title: const Text('Desbloquear con huella o PIN'), value: _biometric, onChanged: _toggleBiometric),
            SwitchListTile(
              title: const Text('Recordar mi carné'),
              value: _rememberCard,
              onChanged: (value) async {
                await Storage.setBool(Session.rememberCardKey, value);
                if (!value) await Storage.saveLastCard(null);
                setState(() => _rememberCard = value);
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
