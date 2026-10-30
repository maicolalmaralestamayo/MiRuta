import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notifications.dart';
import '../../services/session.dart';
import '../../services/sync.dart';
import '../applications/applications_screen.dart';
import '../chat/conversations_screen.dart';
import '../trips/trips_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// Navegación principal. Mientras la app está abierta sincroniza con la
/// frecuencia elegida por el usuario.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.requestPermissions();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final session = context.read<Session>();
    final seconds = session.settings.integer('trips_poll_foreground_seconds', 60);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => SyncService.run(session.api).catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<Session>();
      SyncService.run(session.api).catchError((_) {});
      session.reloadMe().catchError((_) {});
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
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
    const pages = [HomeScreen(), TripsScreen(), ApplicationsScreen(), ConversationsScreen(), MoreScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.directions_bus_outlined), selectedIcon: Icon(Icons.directions_bus), label: 'Viajes'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Solicitudes'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Mensajes'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }
}
