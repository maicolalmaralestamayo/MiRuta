import 'package:flutter/material.dart';

import '../models/models.dart';
import 'admin/admin_menu.dart';
import 'auth/other_registration_data_screen.dart';
import 'guest/developer_chat_screen.dart';
import 'profile/profile_screen.dart';
import 'qr/assign_by_qr.dart';
import 'qr/my_qr_screen.dart';
import 'qr/pending_scans_screen.dart';
import 'trips/trip_detail_screen.dart';
import 'worker/child_form_screen.dart';
import 'worker/children_screen.dart';
import 'worker/entities_screen.dart';
import 'worker/itinerary_screen.dart';
import 'worker/roles_screen.dart';

/// Pestañas de la barra principal (docs/11 §11.10).
enum MainTab { home, trips, messages, more }

/// Pestaña elegida de la pantalla principal (HomeShell la escucha).
abstract final class MainTabs {
  static final current = ValueNotifier<MainTab>(MainTab.home);

  /// Va a esa pestaña: desde una pantalla interior, vuelve antes a la principal.
  static void go(BuildContext context, MainTab tab) {
    current.value = tab;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// Rutas de la app 3.0. Cada pantalla se abre siempre desde aquí, así quien
/// la implementa solo cambia el destino (ver app/V3-APP-BASE.md).
abstract final class AppRoutes {
  static Future<T?> _push<T>(BuildContext context, Widget screen) => Navigator.push<T>(context, MaterialPageRoute(builder: (_) => screen));

  // Base

  /// Perfil (docs/11 §11.18).
  static Future<void> profile(BuildContext context) => _push(context, const ProfileScreen());

  /// «Otros datos del registro» (docs/11 §11.5).
  static Future<void> registrationExtras(BuildContext context) => _push(context, const OtherRegistrationDataScreen());

  /// «Hablar con el desarrollador».
  static Future<void> developerChat(BuildContext context) => _push(context, const GuestConversationsScreen());

  /// Gestión (Más → Gestión): solo las entradas permitidas.
  static Future<void> management(BuildContext context) => _push(context, const AdminMenu());

  // Pantallas del trabajador (stubs en ui/worker/)

  static Future<void> children(BuildContext context) => _push(context, const ChildrenScreen());

  /// Formulario de un hijo ([child] null = hijo nuevo).
  static Future<void> childForm(BuildContext context, [Child? child]) => _push(context, ChildFormScreen(child: child));

  /// Agregar un hijo ya registrado por otra persona (por su carné).
  static Future<void> addRegisteredChild(BuildContext context) => _push(context, const ChildFormScreen(registered: true));

  static Future<void> entities(BuildContext context) => _push(context, const MyEntitiesScreen());

  /// Itinerario y parada (de la Entidad elegida).
  static Future<void> itinerary(BuildContext context) => _push(context, const ItineraryStopScreen());

  /// Roles (de la Entidad elegida).
  static Future<void> roles(BuildContext context) => _push(context, const MyRolesScreen());

  /// Viajes: la pestaña Viajes de la barra principal.
  static void trips(BuildContext context) => MainTabs.go(context, MainTab.trips);

  /// Detalle de un viaje.
  static Future<void> tripDetail(BuildContext context, String tripId) => _push(context, TripDetailScreen(tripId: tripId));

  // QR (stub en ui/qr/)

  static Future<void> myQr(BuildContext context) => _push(context, const MyQrScreen());

  /// Alta directa en un itinerario escaneando el QR (members.assign_by_qr).
  static Future<void> assignByQr(BuildContext context) => assignItineraryByQr(context);

  /// Escaneos hechos sin conexión y su resultado al enviarlos.
  static Future<void> pendingScans(BuildContext context) => _push(context, const PendingScansScreen());
}
