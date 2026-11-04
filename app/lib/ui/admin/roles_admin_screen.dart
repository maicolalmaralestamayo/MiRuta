import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Roles configurables (gestión, docs/11 §11.16). STUB de la base 3.0 — lo
/// rehace «gestión». Crear, editar y eliminar roles con sus operaciones y
/// ámbitos (RolesApi.all / operations; POST/PATCH/DELETE /roles), el rol por
/// defecto y los roles aprobadores.
class RolesAdminScreen extends StatelessWidget {
  const RolesAdminScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Roles',
        owner: 'gestión',
        description: 'Roles de la aplicación: su nombre, sus operaciones con su ámbito, si se pueden solicitar, quién los aprueba y el rol por defecto.',
      );
}
