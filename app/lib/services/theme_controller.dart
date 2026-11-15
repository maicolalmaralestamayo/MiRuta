import 'package:flutter/material.dart';

import '../core/storage.dart';

/// Tema de la app (docs/11 §11.62): claro, oscuro o automático (según el
/// teléfono, por omisión). Se elige en el inicio de sesión y en Inicio →
/// Acciones → «Tema»; se guarda en el teléfono (no se borra al cerrar sesión).
class ThemeController {
  static const _key = 'app.theme_mode';

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static const names = {ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro', ThemeMode.system: 'Automático'};

  static Future<void> load() async {
    mode.value = switch (await Storage.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    await Storage.setString(_key, value == ThemeMode.system ? null : value.name);
  }
}

/// Selector Claro · Oscuro · Automático (íconos sol, luna y engranaje).
class ThemeModeSelector extends StatelessWidget {
  final bool compact;

  const ThemeModeSelector({super.key, this.compact = true});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, current, _) => SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        segments: [
          for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
            ButtonSegment(
              value: m,
              tooltip: 'Tema ${ThemeController.names[m]!.toLowerCase()}',
              icon: Icon(switch (m) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.settings_suggest_outlined,
              }),
              label: compact ? null : Text(ThemeController.names[m]!),
            ),
        ],
        selected: {current},
        onSelectionChanged: (s) => ThemeController.set(s.first),
      ),
    );
  }
}
