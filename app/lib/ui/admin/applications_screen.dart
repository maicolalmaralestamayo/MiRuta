import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Solicitudes por resolver (gestión). STUB de la base 3.0 — lo rehace «gestión».
///
/// GET /applications?filter[toResolve]=true (entrar en una Entidad,
/// itinerario y parada, rol). Aprobar o rechazar con motivo:
/// MembershipsApi.resolveApplication. La tarjeta de quien solicita: UserCard.
class ApplicationsToResolveScreen extends StatelessWidget {
  const ApplicationsToResolveScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Solicitudes por resolver',
        owner: 'gestión',
        entitySelector: true,
        description: 'Solicitudes de entrada en una Entidad, de itinerario y parada y de roles que usted puede aprobar o rechazar.',
      );
}
