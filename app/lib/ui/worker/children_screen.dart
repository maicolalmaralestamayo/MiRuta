import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Hijos (docs/11 §11.18). STUB de la base 3.0 — lo hace «pantallas del trabajador».
///
/// Contenido: secciones «Con derecho a viajar» y «Desactivados» (en gris) con
/// ChildCard, en SelectableCardList. Acciones: Crear (hijo nuevo, abre
/// ChildFormScreen()), Agregar (ya registrado, por carné: ChildrenApi.add),
/// Editar (una), Desactivar / Reactivar (una o varias) y Eliminar (rojo).
/// Servicio: services/api/children_api.dart.
class ChildrenScreen extends StatelessWidget {
  const ChildrenScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Hijos',
        owner: 'pantallas del trabajador',
        description: 'Sus hijos con derecho a viajar y los desactivados. Desde aquí podrá crear, agregar, editar, desactivar y eliminar hijos.',
      );
}
