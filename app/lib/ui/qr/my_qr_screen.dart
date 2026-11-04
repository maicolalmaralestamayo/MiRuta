import 'package:flutter/material.dart';

import '../widgets/pending_screen.dart';

/// Mi QR (docs/11 §11.8; docs/04-api.md §4.5). STUB de la base 3.0 — lo hace «QR».
///
/// QR dinámico `MR1.…` firmado en el teléfono, renovado cada 15 s, con
/// FLAG_SECURE; certificado con POST /me/qr-devices.
class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingScreen(
        title: 'Mi QR',
        owner: 'QR',
        description: 'Su código QR personal, que sirve en todas sus Entidades: para subir al transporte y para que un jefe le dé de alta en un itinerario.',
      );
}
