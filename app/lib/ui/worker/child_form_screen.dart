import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../widgets/pending_screen.dart';

/// Formulario de un hijo (docs/11 §11.18). STUB de la base 3.0 — lo hace
/// «pantallas del trabajador».
///
/// [child] null = hijo nuevo. Contenido: foto; nombres, apellidos y carné
/// editables; sexo, nacimiento y derecho a viajar de solo lectura
/// (IdentityCard.birthDate / sex); «También lo tiene declarado» (Child.parents).
/// Acciones: Guardar, Desactivar / Reactivar, Eliminar (rojo).
/// Servicio: services/api/children_api.dart.
class ChildFormScreen extends StatelessWidget {
  final Child? child;

  const ChildFormScreen({super.key, this.child});

  @override
  Widget build(BuildContext context) => PendingScreen(
        title: child == null ? 'Hijo nuevo' : 'Hijo',
        owner: 'pantallas del trabajador',
        description: child == null
            ? 'Aquí podrá añadir un hijo con sus nombres, apellidos y carné de identidad.'
            : 'Datos de ${child!.fullName}: podrá corregirlos, desactivarlo o quitarlo.',
      );
}
