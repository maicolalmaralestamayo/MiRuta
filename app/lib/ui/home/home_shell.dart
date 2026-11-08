import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notifications.dart';
import '../../services/session.dart';
import '../../services/shared_location.dart';
import '../chat/conversations_screen.dart';
import '../management/management_screen.dart';
import '../navigation.dart';
import '../shared/shared_location_screen.dart';
import '../trips/trip_line_screen.dart';
import '../trips/trips_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// Pantalla principal: las cuatro pestañas (Inicio · Gestión · Viajes · Más).
/// Mientras está abierta consulta al servidor con su frecuencia; atiende lo
/// tocado en las notificaciones y las ubicaciones compartidas desde otras apps.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.requestPermissions();
    MainTabs.current.value = MainTab.home;
    Notifications.tapped.addListener(_onTapped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onTapped();
      SharedLocation.listen(_onShared);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<Session>();
    if (state == AppLifecycleState.resumed) {
      session.resume();
    } else if (state == AppLifecycleState.paused) {
      session.pause();
    }
  }

  void _onTapped() {
    final payload = Notifications.tapped.value;
    if (payload == null || !mounted) return;
    Notifications.tapped.value = null;
    if (payload.startsWith('trip:')) {
      MainTabs.go(context, MainTab.trips);
      push(context, TripLineScreen(tripId: payload.substring(5)));
    } else if (payload == 'gestion') {
      MainTabs.go(context, MainTab.management);
    } else if (payload.startsWith('conversation')) {
      MainTabs.go(context, MainTab.more);
      push(context, const ConversationsScreen());
    } else if (payload == 'update' || payload == 'olvide') {
      MainTabs.go(context, MainTab.more);
    }
  }

  void _onShared(String text) {
    if (!mounted) return;
    push(context, SharedLocationScreen(text: text));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notifications.tapped.removeListener(_onTapped);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MainTab>(
      valueListenable: MainTabs.current,
      builder: (context, tab, _) => IndexedStack(
        index: tab.index,
        children: const [HomeScreen(), ManagementScreen(), TripsScreen(), MoreScreen()],
      ),
    );
  }
}
