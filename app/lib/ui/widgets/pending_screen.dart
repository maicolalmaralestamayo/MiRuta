import 'package:flutter/material.dart';

import '../navigation.dart';
import 'app_scaffold.dart';
import 'entity_selector.dart';

/// Pantalla provisional («stub») de la base 3.0: tiene ya su ruta, su título y
/// la forma común (AppScaffold), y dice qué contendrá. La sustituye quien la
/// implemente (ver app/V3-APP-BASE.md).
class PendingScreen extends StatelessWidget {
  final String title;

  /// Qué contendrá, según docs/11 §11.18.
  final String description;

  /// Quién la hace: «pantallas del trabajador», «gestión» o «QR».
  final String owner;

  /// La pantalla lleva selector de Entidad.
  final bool entitySelector;
  final MainTab tab;

  const PendingScreen({super.key, required this.title, required this.description, required this.owner, this.entitySelector = false, this.tab = MainTab.home});

  @override
  Widget build(BuildContext context) {
    return AppScaffold.list(title: title, tab: tab, children: [
      if (entitySelector) const EntitySelector(),
      Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.construction),
              const SizedBox(width: 12),
              Expanded(child: Text('Pantalla en preparación', style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            Text(description),
            const SizedBox(height: 8),
            Text('Parte: $owner', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    ]);
  }
}
