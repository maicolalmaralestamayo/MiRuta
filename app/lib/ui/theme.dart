import 'package:flutter/material.dart';

/// Colores: verde petróleo como color principal y un rojo intenso para la
/// sobresaturación, que debe verse de inmediato.
const seed = Color(0xFF00796B);
const overloadColor = Color(0xFFD32F2F);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}
