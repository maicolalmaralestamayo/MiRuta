import 'package:flutter/material.dart';

/// Paleta de la app: azul marino y naranja puros.
///
/// - Azul marino: #000080 (navy, CSS/X11).
/// - Naranja: #FFA500 (orange, CSS/X11).
///
/// El rojo de sobresaturación se mantiene aparte para que se vea de inmediato.
const navy = Color(0xFF000080);
const orange = Color(0xFFFFA500);
const overloadColor = Color(0xFFD32F2F);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: navy, brightness: brightness);
  final scheme = dark
      ? base.copyWith(
          // En modo oscuro el azul marino puro no contrasta con el fondo:
          // se usa como superficie de los contenedores y el naranja como acento.
          primary: orange,
          onPrimary: Colors.black,
          primaryContainer: navy,
          onPrimaryContainer: Colors.white,
          secondary: orange,
          onSecondary: Colors.black,
          secondaryContainer: const Color(0xFF4D3200),
          onSecondaryContainer: const Color(0xFFFFDDB0),
          surface: const Color(0xFF0B0B1E),
        )
      : base.copyWith(
          primary: navy,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFDDE1FF),
          onPrimaryContainer: navy,
          secondary: orange,
          onSecondary: Colors.black,
          secondaryContainer: const Color(0xFFFFE0B2),
          onSecondaryContainer: const Color(0xFF4D3200),
          tertiary: orange,
          onTertiary: Colors.black,
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: orange),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: orange,
      foregroundColor: navy,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: orange,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? navy : (dark ? Colors.white70 : navy),
          )),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: orange),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}
