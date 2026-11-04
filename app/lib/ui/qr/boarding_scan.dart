import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../models/models.dart';
import '../../services/qr/qr_codes.dart';
import '../../services/qr/qr_store.dart';
import '../trips/trip_context.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'qr_scanner_screen.dart';

/// Hijo que se puede marcar al subir.
class BoardingChildOption {
  final String id;
  final String fullName;
  final String? photoUrl;

  /// Ya subió en este trayecto (con otra persona): no se puede marcar.
  final bool alreadyBoarded;

  const BoardingChildOption({required this.id, required this.fullName, this.photoUrl, this.alreadyBoarded = false});
}

/// Lo que se muestra a quien escanea antes de registrar la subida.
class BoardingCandidate {
  final String userId;
  final String fullName;
  final String? photoUrl;
  final List<String> lines;

  /// `itinerary` | `entity` | null.
  final String? outsider;
  final bool canAllowOutsider;
  final QrKind kind;
  final String? warning;

  /// No se puede registrar (p. ej. ya subió).
  final bool blocked;
  final List<BoardingChildOption> children;

  const BoardingCandidate({
    required this.userId,
    required this.fullName,
    this.photoUrl,
    this.lines = const [],
    this.outsider,
    this.canAllowOutsider = false,
    required this.kind,
    this.warning,
    this.blocked = false,
    this.children = const [],
  });

  String? get outsiderText => switch (outsider) {
        'itinerary' => 'No es de este itinerario.',
        'entity' => 'No es de la Entidad de este viaje.',
        _ => null,
      };
}

/// Decisión de quien escanea.
class BoardingDecision {
  final List<String> childIds;
  final bool allowOutsider;

  const BoardingDecision(this.childIds, this.allowOutsider);
}

/// Escanea QR y registra subidas en [leg] (docs/11 §11.8 y §11.11) hasta
/// que se vuelve atrás en el escáner. Con conexión verifica con POST
/// /qr-scans y registra con POST /trip-boardings; sin conexión verifica en el
/// teléfono con la lista guardada y deja la subida en la cola (POST
/// /offline-scans al sincronizar). Devuelve si registró alguna.
Future<bool> scanBoardings(BuildContext context, TripContext trip, TripLeg leg) async {
  var any = false;
  while (true) {
    if (!context.mounted) break;
    final qr = await scanQrCode(context, title: 'Subida · ${leg.directionLabel}');
    if (qr == null || !context.mounted) break;
    final registered = await registerBoardingFromQr(context, trip, leg, qr, DateTime.now());
    any = any || registered;
  }
  return any;
}

/// Procesa un QR leído a la hora [scannedAt]. Devuelve si quedó registrada
/// (o guardada en la cola).
Future<bool> registerBoardingFromQr(BuildContext context, TripContext trip, TripLeg leg, String qr, DateTime scannedAt) async {
  final api = context.api;
  BoardingCandidate candidate;
  var online = true;
  try {
    final document = await api.post(
        '/qr-scans',
        resourceData('qr-scans', attributes: {'qr': qr, 'purpose': 'boarding', 'scannedAt': scannedAt.toUtc().toIso8601String()}, relationships: {
          'tripLeg': ResourceId('trip-legs', leg.id),
        }));
    candidate = _fromScan(document.resource, trip);
  } on ApiException catch (error) {
    if (!error.isNetwork) {
      if (context.mounted) await _problem(context, error.message);
      return false;
    }
    online = false;
    if (!context.mounted) return false;
    try {
      candidate = await _offlineCandidate(context, trip, leg, qr, scannedAt);
    } on QrException catch (problem) {
      if (context.mounted) await _problem(context, problem.message);
      return false;
    }
  }
  if (!context.mounted) return false;

  final decision = await showBoardingSheet(context, candidate, offline: !online);
  if (decision == null || !context.mounted) return false;

  if (online) {
    try {
      await _post(context, leg, qr, scannedAt, decision);
      await _remember(qr, leg, candidate, decision);
      if (context.mounted) showMessage(context, 'Subida registrada: ${candidate.fullName}');
      return true;
    } on ApiException catch (error) {
      if (!error.isNetwork) {
        if (error.hasCode('OUTSIDER_CONFIRMATION_REQUIRED') && candidate.canAllowOutsider && context.mounted) {
          final entity = error.errors.first.meta['outsider'] == 'entity';
          if (await confirm(context, 'Persona de fuera', '${candidate.fullName} es de ${entity ? 'otra Entidad' : 'otro itinerario'}. ¿La deja subir?') &&
              context.mounted) {
            return runAction(context, () async {
              await _post(context, leg, qr, scannedAt, BoardingDecision(decision.childIds, true));
              await _remember(qr, leg, candidate, decision);
            }, success: 'Subida registrada: ${candidate.fullName}');
          }
          return false;
        }
        if (context.mounted) await _problem(context, error.message);
        return false;
      }
      // Se perdió la conexión al registrar: se guarda en la cola.
    }
  }

  await QrStore.enqueue(
    purpose: 'boarding',
    qr: qr,
    scannedAt: scannedAt,
    label: candidate.fullName,
    tripLegId: leg.id,
    tripId: trip.trip.id,
    childIds: decision.childIds,
    allowOutsider: decision.allowOutsider,
  );
  await _remember(qr, leg, candidate, decision);
  if (context.mounted) showMessage(context, 'Sin conexión: subida de ${candidate.fullName} guardada. Se enviará al recuperar la conexión.');
  return true;
}

Future<void> _post(BuildContext context, TripLeg leg, String qr, DateTime scannedAt, BoardingDecision decision) => context.api.post(
    '/trip-boardings',
    resourceData('trip-boardings', attributes: {
      'method': 'qr',
      'qr': qr,
      'childIds': decision.childIds,
      'allowOutsider': decision.allowOutsider,
      'scannedAt': scannedAt.toUtc().toIso8601String(),
    }, relationships: {
      'tripLeg': ResourceId('trip-legs', leg.id),
    }));

/// Recuerda en el teléfono el código usado y la subida del trayecto.
Future<void> _remember(String qr, TripLeg leg, BoardingCandidate candidate, BoardingDecision decision) async {
  final nonce = dynamicQrNonceKey(qr);
  if (nonce != null) await QrStore.markNonceUsed(nonce);
  await QrStore.addLegBoarding(leg.id, userId: candidate.userId, printed: candidate.kind == QrKind.printed, childIds: decision.childIds);
}

/// `persona:nonce` de un MR1 (sin verificar), para recordarlo como usado.
String? dynamicQrNonceKey(String qr) {
  final parts = qr.trim().split('.');
  if (parts.length != 5 || parts[0] != 'MR1') return null;
  final bytes = base64UrlDecodeStrict(parts[3]);
  if (bytes == null) return null;
  try {
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is Map && payload['u'] is int && payload['n'] is String) return '${payload['u']}:${payload['n']}';
  } catch (_) {
    // No es JSON: no hay nada que recordar.
  }
  return null;
}

Future<void> _problem(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('No se puede registrar'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar'))],
      ),
    );

BoardingCandidate _fromScan(Resource r, TripContext trip) {
  final memberships = [for (final m in (r.attributes['memberships'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
  final here = memberships.where((m) => '${m['entityId']}' == trip.trip.entityId).firstOrNull;
  final entities = [for (final e in (r.attributes['entities'] as List? ?? const [])) '$e'];
  final kind = r.string('kind') == 'printed' ? QrKind.printed : QrKind.dynamic;
  final alreadyBoarded = r.boolean('alreadyBoarded');
  return BoardingCandidate(
    userId: r.string('userId') ?? '',
    fullName: r.string('fullName') ?? '',
    photoUrl: r.string('photoUrl'),
    lines: [
      entities.isEmpty ? 'Sin Entidad' : entities.join(' • '),
      if (here != null && here['itineraryName'] != null) '${here['itineraryName']}${here['stopLandmark'] != null ? ' · ${here['stopLandmark']}' : ''}',
      if (kind == QrKind.printed) 'QR impreso',
    ],
    outsider: r.string('outsider'),
    canAllowOutsider: r.boolean('canAllowOutsider'),
    kind: kind,
    warning: r.string('warning'),
    blocked: alreadyBoarded || r.boolean('alreadyUsed'),
    children: [
      for (final c in (r.attributes['children'] as List? ?? const []))
        BoardingChildOption(
          id: '${(c as Map)['id']}',
          fullName: '${c['fullName'] ?? ''}',
          photoUrl: c['photoUrl'] as String?,
          alreadyBoarded: c['alreadyBoarded'] == true && c['boardedWithThisPerson'] != true,
        ),
    ],
  );
}

/// Verificación sin conexión con la lista guardada (V3-PARTE-B §1).
Future<BoardingCandidate> _offlineCandidate(BuildContext context, TripContext trip, TripLeg leg, String qr, DateTime scannedAt) async {
  final me = context.me;
  final serverKey = await QrStore.serverPublicKey();
  if (serverKey == null) {
    throw const QrException('QR_NO_SERVER_KEY', 'Sin conexión y sin la lista para escanear: sincronice con conexión al menos una vez.');
  }
  final roster = await QrStore.roster(trip.trip.entityId);
  final used = await QrStore.usedNonces();
  final check = verifyQr(
    qr,
    serverPublicKey: serverKey,
    now: scannedAt,
    isNonceUsed: (u, n) => used.contains('$u:$n'),
    printedVersionOf: (u) {
      final w = roster?.worker('$u');
      return (inRoster: w != null, version: w?.printedQrVersion);
    },
  );
  final userId = '${check.userId}';
  final (worker, _) = await QrStore.findWorker(userId, entityId: trip.trip.entityId);
  final inEntity = roster?.worker(userId) != null;
  final outsider = !inEntity ? 'entity' : (roster!.worker(userId)!.itineraryId == trip.trip.itineraryId ? null : 'itinerary');
  final boarded = await QrStore.legBoardings(leg.id);
  final already = boarded.userIds.contains(userId);
  final children = roster?.childrenOf(userId) ?? const <RosterChild>[];
  return BoardingCandidate(
    userId: userId,
    fullName: worker?.fullName ?? 'Persona n.º $userId (no está en la lista guardada)',
    photoUrl: worker?.photoUrl,
    lines: [
      if (worker?.itineraryName != null) '${worker!.itineraryName}${worker.stopLandmark != null ? ' · ${worker.stopLandmark}' : ''}',
      if (check.kind == QrKind.printed) 'QR impreso',
      'Verificado sin conexión',
    ],
    outsider: outsider,
    canAllowOutsider: trip.can(me, Op.trackingAllowOutsiders),
    kind: check.kind,
    warning: already
        ? (check.kind == QrKind.printed
            ? 'Este QR impreso ya se usó en este trayecto: puede ser una copia.'
            : 'Esta persona ya subió en este trayecto.')
        : null,
    blocked: already,
    children: [
      for (final c in children) BoardingChildOption(id: c.childId, fullName: c.fullName, photoUrl: c.photoUrl, alreadyBoarded: boarded.childIds.contains(c.childId)),
    ],
  );
}

/// Tarjeta de la persona (con foto) y casillas de los hijos que suben.
/// [initial]: hijos ya marcados (corrección); [actionLabel]: texto del botón.
Future<BoardingDecision?> showBoardingSheet(BuildContext context, BoardingCandidate candidate,
    {bool offline = false, Set<String> initial = const {}, String? actionLabel}) {
  final selected = <String>{...initial};
  return showModalBottomSheet<BoardingDecision>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final theme = Theme.of(context);
      final outsiderBlocked = candidate.outsider != null && !candidate.canAllowOutsider;
      final canRegister = !candidate.blocked && !outsiderBlocked;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 12, 8, 12), children: [
            Center(
              child: CardImage(url: candidate.photoUrl, icon: Icons.person, round: true, size: 120),
            ),
            const SizedBox(height: 8),
            InfoCard(title: candidate.fullName, lines: candidate.lines),
            if (candidate.warning != null) _Banner(icon: Icons.warning_amber, text: candidate.warning!, color: Colors.orange),
            if (candidate.outsiderText != null)
              _Banner(
                icon: Icons.alt_route,
                color: outsiderBlocked ? theme.colorScheme.error : Colors.orange,
                text: outsiderBlocked
                    ? '${candidate.outsiderText} No tiene permiso para dejar subir a personas de fuera.'
                    : '${candidate.outsiderText} Decida si la deja subir.',
              ),
            if (offline) const _Banner(icon: Icons.cloud_off, color: Colors.blueGrey, text: 'Sin conexión: la subida se guardará y se enviará después.'),
            if (candidate.children.isNotEmpty) ...[
              const SectionHeader('Hijos que suben con él o ella'),
              for (final child in candidate.children)
                CheckboxListTile(
                  value: selected.contains(child.id),
                  secondary: CardImage(url: child.photoUrl, icon: Icons.child_care, round: true, size: 40),
                  title: Text(child.fullName),
                  subtitle: child.alreadyBoarded ? const Text('Ya subió en este trayecto') : null,
                  onChanged: child.alreadyBoarded || !canRegister
                      ? null
                      : (value) => setState(() => value == true ? selected.add(child.id) : selected.remove(child.id)),
                ),
            ],
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: canRegister ? () => Navigator.pop(context, BoardingDecision(selected.toList(), candidate.outsider != null)) : null,
                icon: const Icon(Icons.how_to_reg),
                label: Text(actionLabel ?? (candidate.outsider != null ? 'Dejar subir' : 'Registrar subida')),
              ),
            ]),
          ]),
        ),
      );
    }),
  );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Banner({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
        child: Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Expanded(child: Text(text))]),
      );
}
