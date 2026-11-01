import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../models/models.dart';
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
  'Seguridad': ['remember_password', 'remember_password_days', 'password_expiry_notice_days'],
  'Aviso de viaje de ida': ['departure_notice_mode', 'departure_notice_minutes_before', 'departure_notice_fixed_time', 'departure_notice_fixed_days_before', 'departure_notice_fallback', 'departure_notice_template'],
  'Aviso de viaje de regreso': ['return_notice_mode', 'return_notice_minutes_before', 'return_notice_fixed_time', 'return_notice_fixed_days_before', 'return_notice_fallback', 'return_notice_template'],
  'Comienzo y atrasos': ['trip_start_notice_enabled', 'trip_delay_notice_enabled'],
  'Paso por paradas': ['stop_notice_scope', 'stop_notice_after_boarding', 'stop_notice_template'],
  'Cambios y cancelaciones': ['change_notice_template', 'cancel_notice_template', 'notify_during_absence'],
  'Saturación del transporte': [
    'saturation_notice_enabled', 'saturation_notice_level', 'saturation_notice_scope', 'saturation_notice_when', 'saturation_notice_minutes_before',
  ],
  'Mensajes': ['trip_chat_notice_enabled', 'conversation_notice_enabled'],
  'Recorrido': ['trip_view', 'tts_enabled', 'share_location', 'location_interval_seconds'],
  'Frecuencias': [
    'background_sync_enabled', 'trips_poll_foreground_seconds', 'trips_poll_background_minutes', 'tracking_poll_foreground_seconds',
    'tracking_poll_background_seconds', 'trip_chat_poll_foreground_seconds', 'trip_chat_poll_background_minutes',
    'conversations_poll_foreground_seconds', 'conversations_poll_background_minutes', 'notices_poll_foreground_seconds', 'notices_poll_background_minutes',
  ],
};

class _SettingsScreenState extends State<SettingsScreen> {
  final _view = GlobalKey<AsyncViewState<(Map<String, SettingDefinition>, UserSettings)>>();
  bool _rememberLogin = true;
  bool _wifiOnly = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    Storage.getBool(Session.rememberLoginKey, fallback: true).then((v) => setState(() => _rememberLogin = v));
    AppUpdates.currentVersionName().then((v) => setState(() => _version = v));
    Storage.getBool(AppUpdates.wifiOnlyKey, fallback: false).then((v) => setState(() => _wifiOnly = v));
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
            const SectionTitle('En este teléfono'),
            SwitchListTile(
              title: const Text('Recordar mi nombre de usuario'),
              subtitle: const Text('Aparece ya escrito al iniciar sesión.', maxLines: 1, overflow: TextOverflow.ellipsis),
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
                if (definitions[key] != null && (key != 'tts_enabled' || operator) && (key != 'saturation_notice_scope' || operator))
                  ListTile(
                    title: Text(definitions[key]!.name),
                    // Explicación breve de una línea y el valor (docs/09 §17).
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((definitions[key]!.description ?? '').isNotEmpty)
                        Text(definitions[key]!.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      Text(describeSetting(definitions[key]!, settings.string(key)), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    trailing: definitions[key]!.valueType == 'boolean'
                        ? Switch(value: settings.string(key) == '1', onChanged: (_) => _edit(definitions[key]!, settings.string(key)))
                        : const Icon(Icons.chevron_right),
                    onTap: () => _edit(definitions[key]!, settings.string(key)),
                    onLongPress: () => _reset(definitions[key]!),
                  ),
            ],
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Mantenga pulsado un ajuste para volver al valor de su Entidad.'),
            ),
            const SectionTitle('Actualizaciones'),
            if (definitions['update_check_hours'] != null)
              ListTile(
                title: Text(definitions['update_check_hours']!.name),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(definitions['update_check_hours']!.description ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  Text(describeSetting(definitions['update_check_hours']!, settings.string('update_check_hours')), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(definitions['update_check_hours']!, settings.string('update_check_hours')),
                onLongPress: () => _reset(definitions['update_check_hours']!),
              ),
            SwitchListTile(
              title: const Text('Descargar actualizaciones solo con Wi-Fi'),
              subtitle: const Text('Las obligatorias se descargan siempre.', maxLines: 1, overflow: TextOverflow.ellipsis),
              value: _wifiOnly,
              onChanged: (value) async {
                await Storage.setBool(AppUpdates.wifiOnlyKey, value);
                setState(() => _wifiOnly = value);
              },
            ),
            BusyListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Buscar actualizaciones ahora'),
              subtitle: Text('Versión instalada: $_version'),
              onTap: () async {
                final update = await AppUpdates.check(context.api);
                if (!context.mounted) return;
                if (update == null) {
                  showMessage(context, 'Tiene la última versión.');
                } else {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateScreen(update: update)));
                }
              },
            ),
            if (me.managesTransport) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(me.isAdmin ? 'Ajustes de la app' : 'Ajustes de la Entidad'),
                subtitle: const Text('Valores para todos los usuarios'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => me.isAdmin ? const GlobalSettingsScreen.app() : const GlobalSettingsScreen.entity())),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
