import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Roles (docs/11 §11.18). STUB de la base 3.0 — lo hace «pantallas del
/// trabajador». Con selector de Entidad.
///
/// Contenido: «Mis roles» (siempre primero RoleCard.worker; después
/// RoleCard.held de membership.extraRoles) y «Solicitudes pendientes».
/// Acciones: Solicitar (un rol: RolesApi.requestable + MembershipsApi.requestRole),
/// Darme de baja (no aplica a Trabajador: RolesApi.remove(heldRole.id)),
/// Cancelar solicitud.
class MyRolesScreen extends StatelessWidget {
  const MyRolesScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Roles',
        owner: 'pantallas del trabajador',
        entitySelector: true,
        description: 'Sus roles en la Entidad elegida y sus solicitudes pendientes. Podrá solicitar un rol, darse de baja de uno y cancelar solicitudes.',
      );
}
