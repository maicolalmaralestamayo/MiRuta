import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Entidades (docs/11 §11.18). STUB de la base 3.0 — lo hace «pantallas del
/// trabajador». Sin selector de Entidad.
///
/// Contenido: «Mis Entidades» (EntityCard de me.memberships) y «Solicitudes
/// pendientes» (MembershipsApi.myApplications(type: entity_membership), con
/// CardChip «Pendiente»). Acciones: Solicitar (requestEntityMembership; para
/// el Administrador, joinEntityAsAdmin), Darme de baja (leaveEntity),
/// Cancelar solicitud (MembershipsApi.cancelApplication).
class MyEntitiesScreen extends StatelessWidget {
  const MyEntitiesScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Entidades',
        owner: 'pantallas del trabajador',
        description: 'Sus Entidades y sus solicitudes pendientes. Podrá solicitar entrar en otra Entidad, darse de baja y cancelar solicitudes.',
      );
}
