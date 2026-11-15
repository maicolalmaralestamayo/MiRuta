import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../services/app_updates.dart';
import '../../services/notifications.dart';
import '../../services/session.dart';
import '../../services/shared_location.dart';
import '../../services/tracking/tracking_service.dart';
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
      _serviceTap();
      SharedLocation.listen(_onShared);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<Session>();
    if (state == AppLifecycleState.resumed) {
      session.resume();
      _serviceTap();
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
    } else if (payload == 'inicio') {
      MainTabs.go(context, MainTab.home);
    } else if (payload.startsWith('conversation')) {
      MainTabs.go(context, MainTab.more);
      push(context, const ConversationsScreen());
    } else if (payload == 'update') {
      // «Actualización disponible»: Más, y empieza la descarga.
      MainTabs.go(context, MainTab.more);
      AppUpdates.installRequested.value++;
    } else if (payload == 'olvide') {
      MainTabs.go(context, MainTab.more);
    } else if (payload == 'gps') {
      // «Mi estado» sin GPS: ajustes de ubicación del teléfono (docs/11 §11.63).
      Geolocator.openLocationSettings();
    } else if (payload == 'permiso') {
      // Sin «Permitir todo el tiempo»: ajustes de permisos de MiRuta.
      Geolocator.openAppSettings();
    }
  }

  /// «Mi estado» (notificación del servicio de ubicación) tocada con la app
  /// cerrada: el servicio lo dejó guardado.
  Future<void> _serviceTap() async {
    await Storage.reload();
    final tap = await Storage.getString(TrackingService.tapKey);
    if (tap == null || tap.isEmpty) return;
    await Storage.setString(TrackingService.tapKey, null);
    Notifications.tapped.value = tap;
  }

  /// Ubicación compartida: una sola pantalla «Ubicación compartida» a la
  /// vez (si llega otra, sustituye a la anterior).
  void _onShared(String text) {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.settings.name != SharedLocationScreen.routeName);
    navigator.push(MaterialPageRoute(settings: const RouteSettings(name: SharedLocationScreen.routeName), builder: (_) => SharedLocationScreen(text: text)));
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
