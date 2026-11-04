import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Itinerario y parada (docs/11 §11.18). STUB de la base 3.0 — lo hace
/// «pantallas del trabajador». Con selector de Entidad.
///
/// Contenido: «Mi itinerario y parada» (ItineraryStopCard.membership de
/// session.selectedMembership; solicitudes pendientes con CardChip) y
/// «Ausencias». Acciones: Solicitar (otro itinerario y parada:
/// MembershipsApi.itineraries / stopsOf / requestItinerary), Darme de baja
/// (MembershipsApi.leaveItinerary), Declarar (ausencia: AbsencesApi.create),
/// Editar, Eliminar.
class ItineraryStopScreen extends StatelessWidget {
  const ItineraryStopScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Itinerario y parada',
        owner: 'pantallas del trabajador',
        entitySelector: true,
        description: 'Su itinerario y su parada en la Entidad elegida, y sus ausencias. Podrá solicitar otro itinerario y parada, darse de baja y declarar ausencias.',
      );
}
