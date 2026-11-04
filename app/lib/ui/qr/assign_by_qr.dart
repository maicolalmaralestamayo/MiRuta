import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/api/memberships_api.dart';
import '../../services/qr/qr_store.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'boarding_scan.dart' show dynamicQrNonceKey;
import 'qr_scanner_screen.dart';

/// Alta directa en un itinerario escaneando el QR de la persona (docs/11
/// §11.8, uso 2; members.assign_by_qr). Con conexión: POST /qr-scans
/// (purpose itinerary_assignment) para ver su tarjeta y sus Entidades, y
/// POST /itinerary-assignments con el itinerario y la parada elegidos.
Future<void> assignItineraryByQr(BuildContext context) async {
  final qr = await scanQrCode(context, title: 'Alta en itinerario', tab: MainTab.more, hint: 'Apunte al código QR de la persona a la que dará de alta.');
  if (qr == null || !context.mounted) return;
  final scannedAt = DateTime.now();
  final api = context.api;
  final me = context.me;

  Resource scan;
  try {
    scan = (await api.post('/qr-scans', resourceData('qr-scans', attributes: {'qr': qr, 'purpose': 'itinerary_assignment', 'scannedAt': scannedAt.toUtc().toIso8601String()})))
        .resource;
  } on ApiException catch (error) {
    if (context.mounted) {
      showMessage(context, error.isNetwork ? 'El alta en un itinerario con QR necesita conexión con el servidor.' : error.message);
    }
    return;
  }
  if (!context.mounted) return;

  final memberships = [
    for (final m in (scan.attributes['memberships'] as List? ?? const []))
      if (me.canInEntity(Op.membersAssignByQr, '${(m as Map)['entityId']}')) Map<String, dynamic>.from(m),
  ];
  final fullName = scan.string('fullName') ?? '';
  if (memberships.isEmpty) {
    await _card(context, scan, 'Esta persona no pertenece a ninguna Entidad en la que usted pueda dar altas. Primero debe entrar en la Entidad.', ask: false);
    return;
  }
  if (scan.boolean('alreadyUsed')) {
    await _card(context, scan, scan.string('warning') ?? 'Este código QR ya se usó. Pida que lo muestre de nuevo.', ask: false);
    return;
  }

  // Entidad (si pertenece a varias en las que puede).
  var membership = memberships.first;
  if (memberships.length > 1) {
    final picked = await pickFrom<Map<String, dynamic>>(context, '¿En qué Entidad?', memberships, (m) => '${m['entityAbbreviation']}',
        subtitle: (m) => m['itineraryName'] == null ? 'Sin itinerario' : 'Ahora: ${m['itineraryName']} · ${m['stopLandmark'] ?? ''}');
    if (picked == null || !context.mounted) return;
    membership = picked;
  }
  final entityId = '${membership['entityId']}';

  final memberships0 = MembershipsApi(api);
  List<Itinerary> itineraries;
  try {
    itineraries = (await memberships0.itineraries(entityId)).where((i) => me.can(Op.membersAssignByQr, entityId: entityId, itineraryId: i.id)).toList();
  } catch (error) {
    if (context.mounted) showError(context, error);
    return;
  }
  if (!context.mounted) return;
  if (itineraries.isEmpty) {
    showMessage(context, 'No hay itinerarios en los que pueda dar altas en esta Entidad.');
    return;
  }

  final itinerary = await pickFrom<Itinerary>(context, 'Itinerario para $fullName', itineraries, (i) => i.name,
      subtitle: (i) => i.id == '${membership['itineraryId']}' ? 'Su itinerario actual' : plural(i.memberCount, 'miembro', 'miembros'));
  if (itinerary == null || !context.mounted) return;

  List<Stop> stops;
  try {
    stops = await memberships0.stopsOf(itinerary.id);
  } catch (error) {
    if (context.mounted) showError(context, error);
    return;
  }
  if (!context.mounted) return;
  final stop = await pickFrom<Stop>(context, 'Parada en ${itinerary.name}', stops, (s) => s.landmark, subtitle: (s) => s.address);
  if (stop == null || !context.mounted) return;

  final previous = membership['itineraryName'];
  final ok = await _card(
    context,
    scan,
    '¿Dar de alta a $fullName en ${itinerary.name}, parada ${stop.landmark}?'
        '${previous != null && '${membership['itineraryId']}' != itinerary.id ? '\n\nDejará el itinerario $previous (conserva sus roles).' : ''}',
  );
  if (!ok || !context.mounted) return;

  await runAction(context, () async {
    await api.post(
        '/itinerary-assignments',
        resourceData('itinerary-assignments', attributes: {'qr': qr, 'scannedAt': scannedAt.toUtc().toIso8601String()}, relationships: {
          'itinerary': ResourceId('itineraries', itinerary.id),
          'stop': ResourceId('stops', stop.id),
        }));
    final nonce = dynamicQrNonceKey(qr);
    if (nonce != null) await QrStore.markNonceUsed(nonce);
  }, success: '$fullName quedó en ${itinerary.name} · ${stop.landmark}');
}

/// Tarjeta de la persona (con foto) y un texto; con [ask], botones para confirmar.
Future<bool> _card(BuildContext context, Resource scan, String text, {bool ask = true}) async {
  final entities = [for (final e in (scan.attributes['entities'] as List? ?? const [])) '$e'];
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Alta en itinerario'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CardImage(url: scan.string('photoUrl'), icon: Icons.person, round: true, size: 110),
          const SizedBox(height: 8),
          InfoCard(title: scan.string('fullName') ?? '', lines: [entities.isEmpty ? 'Sin Entidad' : entities.join(' • ')]),
          const SizedBox(height: 8),
          Text(text),
        ]),
      ),
      actions: [
        if (ask) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, ask), child: Text(ask ? 'Dar de alta' : 'Aceptar')),
      ],
    ),
  );
  return result == true;
}
