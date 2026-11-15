import 'package:flutter/material.dart';

import '../core/storage.dart';

/// Tema de la app (docs/11 §11.62): claro, oscuro o automático (según el
/// teléfono, por omisión). Se elige con un solo botón en el inicio de sesión
/// y en la barra de Inicio (docs/11 §11.63); se guarda en el teléfono (no se borra al cerrar sesión).
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

/// Selector de tema en un solo botón (docs/11 §11.63): muestra el icono del
/// modo actual y al tocarlo abre un menú con Claro, Oscuro y Automático.
class ThemeModeSelector extends StatelessWidget {
  /// Color del icono (p. ej. blanco sobre la barra).
  final Color? color;

  const ThemeModeSelector({super.key, this.color});

  static IconData iconOf(ThemeMode m) => switch (m) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.settings_suggest_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, current, _) => PopupMenuButton<ThemeMode>(
        tooltip: 'Tema: ${ThemeController.names[current]!.toLowerCase()}',
        icon: Icon(iconOf(current), color: color),
        initialValue: current,
        onSelected: ThemeController.set,
        itemBuilder: (context) => [
          for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
            CheckedPopupMenuItem(
              value: m,
              checked: m == current,
              child: Row(children: [Icon(iconOf(m)), const SizedBox(width: 12), Text(ThemeController.names[m]!)]),
            ),
        ],
      ),
    );
  }
}
