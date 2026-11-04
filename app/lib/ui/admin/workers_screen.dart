import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Trabajadores (gestión). STUB de la base 3.0 — lo rehace «gestión».
///
/// Lista de pertenencias (GET /workers, filtros entity, itinerary, active,
/// search) con UserCard.worker; registro por el Administrador (POST /workers
/// con nombres, carné, hasPhone, usuario y contraseña propuestos:
/// AccountsApi.usernameSuggestion / passwordSuggestion) mostrando después la
/// tarjeta, el usuario y la contraseña con botones para copiar y compartir;
/// asignar itinerario y parada, roles (RolesApi.assign), desactivar, dar de
/// baja, QR impreso (workers.printed_qr). Permisos: workers.*, members.assign,
/// roles.assign, entities.assign_members.
class WorkersScreen extends StatelessWidget {
  /// Limitar a esos itinerarios (Jefe de itinerario).
  final List<String>? itineraryIds;

  const WorkersScreen({super.key, this.itineraryIds});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Trabajadores',
        owner: 'gestión',
        description: 'Consultar, registrar (con o sin teléfono) y editar trabajadores, con su itinerario, su parada y sus roles.',
      );
}
