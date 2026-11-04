import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notifications.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../chat/conversations_screen.dart';
import '../navigation.dart';
import '../trips/trips_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// Pantalla principal: las cuatro pestañas de la barra principal (Inicio,
/// Viajes, Mensajes y Más). Cada pestaña es un AppScaffold con su propia
/// barra; las pantallas interiores vuelven aquí con MainTabs.go. Mientras la
/// app está abierta sincroniza con la frecuencia elegida por el usuario.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// Minutos fuera de la app tras los que se comprueba si hay que volver a
  /// pedir la contraseña ("Recordar contraseña", docs/09 §17).
  static const _lockAfter = Duration(minutes: 5);

  Timer? _timer;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.requestPermissions();
    MainTabs.current.value = MainTab.home;
    _startTimer();
    // Recién registrado: «Otros datos del registro» (docs/11 §11.5).
    if (context.read<Session>().justRegistered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppRoutes.registrationExtras(context);
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final session = context.read<Session>();
    final seconds = session.settings.integer('trips_poll_foreground_seconds', 60);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => SyncService.run(session.api).catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<Session>();
    if (state == AppLifecycleState.resumed) {
      if (_pausedAt != null && DateTime.now().difference(_pausedAt!) > _lockAfter) {
        session.needsPassword().then((needed) {
          if (needed) session.lock();
        });
      }
      _pausedAt = null;
      SyncService.run(session.api).catchError((_) {});
      session.reloadMe().catchError((_) {});
      session.connection.start();
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      _timer?.cancel();
      session.connection.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MainTab>(
      valueListenable: MainTabs.current,
      builder: (context, tab, _) => IndexedStack(
        index: tab.index,
        children: const [HomeScreen(), TripsScreen(), ConversationsScreen(), MoreScreen()],
      ),
    );
  }
}
