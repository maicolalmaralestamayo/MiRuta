import 'package:flutter/material.dart';

import '../../core/json_api.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// «Ya subí» (solo miembros del itinerario). Los hijos que suben con él los
/// marca quien escanea su QR (docs/11 §11.11); la parte «QR» rehará la subida.
Future<void> selfBoarding(BuildContext context, TripLeg leg) async {
  await runAction(context, () => context.api.post('/trip-boardings', resourceData('trip-boardings', attributes: {
        'method': 'self',
      }, relationships: {'tripLeg': ResourceId('trip-legs', leg.id)})), success: 'Subida registrada');
}
