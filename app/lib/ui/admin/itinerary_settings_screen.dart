import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Ajustes por itinerario y parada (gestión, docs/11 §11.17). STUB de la base
/// 3.0 — lo hace «gestión». GET/PATCH/DELETE /itinerary-settings y
/// /itinerary-stop-settings (settings.itinerary).
class ItinerarySettingsScreen extends StatelessWidget {
  const ItinerarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Ajustes por itinerario',
        owner: 'gestión',
        entitySelector: true,
        description: 'Ajustes del viaje y del recorrido de cada itinerario y de cada parada dentro de él.',
      );
}
