import 'package:flutter/material.dart';

/// Pestañas de la barra principal (docs/12 §3): Inicio · Gestión · Viajes · Más.
enum MainTab { home, management, trips, more }

/// Pestaña elegida de la pantalla principal (HomeShell la escucha).
abstract final class MainTabs {
  static final current = ValueNotifier<MainTab>(MainTab.home);

  /// Va a esa pestaña: desde una pantalla interior, vuelve antes a la principal.
  static void go(BuildContext context, MainTab tab) {
    current.value = tab;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

Future<T?> push<T>(BuildContext context, Widget screen) => Navigator.push<T>(context, MaterialPageRoute(builder: (_) => screen));
