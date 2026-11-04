import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/templates.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/selection.dart';

/// Piezas comunes de las pantallas del trabajador (docs/11 §11.18).

/// Claves de selección: cada pantalla mezcla tarjetas de distinto tipo
/// (pertenencias, solicitudes, ausencias…), así que la clave lleva un prefijo.
abstract final class SelectionKeys {
  static String application(Application a) => 'application:${a.id}';

  static bool isApplication(String key) => key.startsWith('application:');

  static String idOf(String key) => key.substring(key.indexOf(':') + 1);

  /// Todas las seleccionadas empiezan por [prefix] (y hay alguna).
  static bool allAre(SelectionController selection, String prefix) => selection.count > 0 && selection.keys.every((k) => k.startsWith(prefix));

  /// Ids de las seleccionadas con ese prefijo.
  static List<String> ids(SelectionController selection, String prefix) => [
        for (final k in selection.keys)
          if (k.startsWith(prefix)) idOf(k),
      ];
}

/// «Solicitada el mar. 03/11/26».
String requestedOn(Application application) => application.createdAt == null ? 'Solicitud pendiente' : 'Solicitada el ${formatDate(application.createdAt!.toLocal())}';

/// Etiqueta «Pendiente» de una solicitud.
Widget pendingChip() => CardChip('Pendiente', color: applicationStatusColor(ApplicationStatus.pending));

/// «Hablar con el desarrollador» al final de las pantallas que se abren desde
/// «Otros datos del registro» (docs/11 §11.5).
class DeveloperChatFooter extends StatelessWidget {
  const DeveloperChatFooter({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Align(alignment: Alignment.centerLeft, child: DeveloperChatButton()),
      );
}
