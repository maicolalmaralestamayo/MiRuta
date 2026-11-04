import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import '../../models/models.dart';

/// Persona de la lista para escanear sin conexión (GET /entities/{id}/scan-roster).
class RosterWorker {
  final String workerId;
  final String userId;
  final String fullName;
  final String? sex;
  final String? photoUrl;
  final String? itineraryId;
  final String? itineraryName;
  final String? stopId;
  final String? stopLandmark;

  /// null = usa el teléfono (cualquier QR impreso suyo está anulado).
  final int? printedQrVersion;

  const RosterWorker({
    required this.workerId,
    required this.userId,
    required this.fullName,
    this.sex,
    this.photoUrl,
    this.itineraryId,
    this.itineraryName,
    this.stopId,
    this.stopLandmark,
    this.printedQrVersion,
  });

  factory RosterWorker.fromJson(Map<String, dynamic> j) => RosterWorker(
        workerId: '${j['workerId']}',
        userId: '${j['userId']}',
        fullName: '${j['fullName'] ?? ''}',
        sex: j['sex'] as String?,
        photoUrl: j['photoUrl'] as String?,
        itineraryId: j['itineraryId']?.toString(),
        itineraryName: j['itineraryName'] as String?,
        stopId: j['stopId']?.toString(),
        stopLandmark: j['stopLandmark'] as String?,
        printedQrVersion: (j['printedQrVersion'] as num?)?.toInt(),
      );
}

/// Hijo con derecho de la lista sin conexión.
class RosterChild {
  final String childId;
  final String fullName;
  final String? sex;
  final String? photoUrl;
  final List<String> parentUserIds;

  const RosterChild({required this.childId, required this.fullName, this.sex, this.photoUrl, this.parentUserIds = const []});

  factory RosterChild.fromJson(Map<String, dynamic> j) => RosterChild(
        childId: '${j['childId']}',
        fullName: '${j['fullName'] ?? ''}',
        sex: j['sex'] as String?,
        photoUrl: j['photoUrl'] as String?,
        parentUserIds: [for (final id in (j['parentUserIds'] as List? ?? const [])) '$id'],
      );
}

/// Lista de una Entidad guardada en el teléfono.
class ScanRoster {
  final String entityId;
  final DateTime? generatedAt;
  final List<RosterWorker> workers;
  final List<RosterChild> children;

  const ScanRoster({required this.entityId, this.generatedAt, this.workers = const [], this.children = const []});

  factory ScanRoster.fromJson(String entityId, Map<String, dynamic> j) => ScanRoster(
        entityId: entityId,
        generatedAt: DateTime.tryParse('${j['generatedAt'] ?? ''}'),
        workers: [for (final w in (j['workers'] as List? ?? const [])) RosterWorker.fromJson(Map<String, dynamic>.from(w as Map))],
        children: [for (final c in (j['children'] as List? ?? const [])) RosterChild.fromJson(Map<String, dynamic>.from(c as Map))],
      );

  RosterWorker? worker(String userId) {
    for (final w in workers) {
      if (w.userId == userId) return w;
    }
    return null;
  }

  List<RosterChild> childrenOf(String userId) => children.where((c) => c.parentUserIds.contains(userId)).toList();

  RosterChild? child(String id) {
    for (final c in children) {
      if (c.childId == id) return c;
    }
    return null;
  }
}

/// Escaneo hecho sin conexión, pendiente de enviar con POST /offline-scans.
class QueuedScan {
  final String lid;
  final String purpose;
  final String qr;
  final DateTime scannedAt;
  final String? tripLegId;
  final String? tripId;
  final List<String> childIds;
  final bool allowOutsider;
  final String? itineraryId;
  final String? stopId;

  /// Para mostrarlo en la lista (nombre de la persona o «Persona sin datos»).
  final String label;

  /// pending | accepted | repeated | discarded | rejected
  final String status;
  final String? code;
  final String? detail;

  const QueuedScan({
    required this.lid,
    required this.purpose,
    required this.qr,
    required this.scannedAt,
    this.tripLegId,
    this.tripId,
    this.childIds = const [],
    this.allowOutsider = false,
    this.itineraryId,
    this.stopId,
    required this.label,
    this.status = 'pending',
    this.code,
    this.detail,
  });

  bool get pending => status == 'pending';

  Map<String, dynamic> toJson() => {
        'lid': lid,
        'purpose': purpose,
        'qr': qr,
        'scannedAt': scannedAt.toUtc().toIso8601String(),
        'tripLegId': tripLegId,
        'tripId': tripId,
        'childIds': childIds,
        'allowOutsider': allowOutsider,
        'itineraryId': itineraryId,
        'stopId': stopId,
        'label': label,
        'status': status,
        'code': code,
        'detail': detail,
      };

  factory QueuedScan.fromJson(Map<String, dynamic> j) => QueuedScan(
        lid: '${j['lid']}',
        purpose: '${j['purpose']}',
        qr: '${j['qr']}',
        scannedAt: DateTime.parse('${j['scannedAt']}').toLocal(),
        tripLegId: j['tripLegId'] as String?,
        tripId: j['tripId'] as String?,
        childIds: [for (final id in (j['childIds'] as List? ?? const [])) '$id'],
        allowOutsider: j['allowOutsider'] == true,
        itineraryId: j['itineraryId'] as String?,
        stopId: j['stopId'] as String?,
        label: '${j['label'] ?? ''}',
        status: '${j['status'] ?? 'pending'}',
        code: j['code'] as String?,
        detail: j['detail'] as String?,
      );

  QueuedScan withResult(String status, String? code, String? detail) => QueuedScan(
        lid: lid,
        purpose: purpose,
        qr: qr,
        scannedAt: scannedAt,
        tripLegId: tripLegId,
        tripId: tripId,
        childIds: childIds,
        allowOutsider: allowOutsider,
        itineraryId: itineraryId,
        stopId: stopId,
        label: label,
        status: status,
        code: code,
        detail: detail,
      );

  /// Elemento de POST /offline-scans.
  Map<String, dynamic> toRequest() => {
        'type': 'offline-scans',
        'lid': lid,
        'attributes': {
          'purpose': purpose,
          'qr': qr,
          'scannedAt': scannedAt.toUtc().toIso8601String(),
          if (purpose == 'boarding') 'childIds': childIds,
          if (purpose == 'boarding') 'allowOutsider': allowOutsider,
        },
        'relationships': {
          if (tripLegId != null) 'tripLeg': {'data': ResourceId('trip-legs', tripLegId!).toJson()},
          if (itineraryId != null) 'itinerary': {'data': ResourceId('itineraries', itineraryId!).toJson()},
          if (stopId != null) 'stop': {'data': ResourceId('stops', stopId!).toJson()},
        },
      };
}

/// Lo que el teléfono que escanea guarda para trabajar sin conexión: clave
/// pública del servidor, listas por Entidad, códigos ya usados, subidas de
/// cada trayecto y la cola de escaneos sin enviar. Todo bajo `user.` (se
/// borra al cerrar sesión).
abstract final class QrStore {
  static const _serverKey = 'user.qr.server_key';
  static const _rosters = 'user.qr.rosters';
  static const _nonces = 'user.qr.nonces';
  static const _legs = 'user.qr.leg_boardings';
  static const _queue = 'user.qr.queue';

  /// Los códigos usados se recuerdan 7 días (V3-PARTE-B §1, paso 7).
  static const nonceDays = 7;

  static Future<String?> serverPublicKey() => Storage.getString(_serverKey);

  static Future<void> setServerPublicKey(String key) => Storage.setString(_serverKey, key);

  static Future<ScanRoster?> roster(String? entityId) async {
    if (entityId == null) return null;
    final all = await Storage.getJson(_rosters);
    final json = all[entityId];
    return json == null ? null : ScanRoster.fromJson(entityId, Map<String, dynamic>.from(json as Map));
  }

  static Future<List<ScanRoster>> rosters() async {
    final all = await Storage.getJson(_rosters);
    return [for (final e in all.entries) ScanRoster.fromJson(e.key, Map<String, dynamic>.from(e.value as Map))];
  }

  static Future<void> saveRoster(String entityId, Map<String, dynamic> attributes) async {
    final all = await Storage.getJson(_rosters);
    all[entityId] = attributes;
    await Storage.setJson(_rosters, all);
  }

  /// Busca a la persona en la lista de [entityId] y, si no, en las demás.
  static Future<(RosterWorker?, ScanRoster?)> findWorker(String userId, {String? entityId}) async {
    final own = await roster(entityId);
    final found = own?.worker(userId);
    if (found != null) return (found, own);
    for (final r in await rosters()) {
      final w = r.worker(userId);
      if (w != null) return (w, r);
    }
    return (null, own);
  }

  // Códigos usados (persona:nonce → caducidad)

  static Future<Set<String>> usedNonces() async {
    final all = await Storage.getJson(_nonces);
    final now = DateTime.now();
    return {for (final e in all.entries) if (DateTime.tryParse('${e.value}')?.isAfter(now) ?? false) e.key};
  }

  static Future<void> markNonceUsed(String key) async {
    final all = await Storage.getJson(_nonces);
    final now = DateTime.now();
    all.removeWhere((_, value) => !(DateTime.tryParse('$value')?.isAfter(now) ?? false));
    all[key] = now.add(const Duration(days: nonceDays)).toIso8601String();
    await Storage.setJson(_nonces, all);
  }

  // Subidas registradas en este teléfono por trayecto (para avisar del
  // impreso usado dos veces y no repetir niños sin conexión).

  static Future<LegBoardings> legBoardings(String legId) async {
    final all = await Storage.getJson(_legs);
    return LegBoardings.fromJson(Map<String, dynamic>.from(all[legId] as Map? ?? const {}));
  }

  static Future<void> addLegBoarding(String legId, {required String userId, required bool printed, List<String> childIds = const []}) async {
    final all = await Storage.getJson(_legs);
    final current = LegBoardings.fromJson(Map<String, dynamic>.from(all[legId] as Map? ?? const {}));
    all[legId] = {
      'users': {...current.userIds, userId}.toList(),
      'printed': {...current.printedUserIds, if (printed) userId}.toList(),
      'children': {...current.childIds, ...childIds}.toList(),
      'at': DateTime.now().toIso8601String(),
    };
    // Se olvidan los trayectos de hace más de una semana.
    final limit = DateTime.now().subtract(const Duration(days: nonceDays));
    all.removeWhere((_, value) => (DateTime.tryParse('${(value as Map)['at']}') ?? DateTime(2000)).isBefore(limit));
    await Storage.setJson(_legs, all);
  }

  // Cola sin conexión

  static Future<List<QueuedScan>> queue() async {
    final json = await Storage.getJson(_queue);
    return [for (final item in (json['items'] as List? ?? const [])) QueuedScan.fromJson(Map<String, dynamic>.from(item as Map))];
  }

  static Future<void> _saveQueue(List<QueuedScan> items) => Storage.setJson(_queue, {'items': [for (final i in items) i.toJson()]});

  static Future<int> pendingCount() async => (await queue()).where((i) => i.pending).length;

  static Future<QueuedScan> enqueue({
    required String purpose,
    required String qr,
    required DateTime scannedAt,
    required String label,
    String? tripLegId,
    String? tripId,
    List<String> childIds = const [],
    bool allowOutsider = false,
    String? itineraryId,
    String? stopId,
  }) async {
    final items = await queue();
    final item = QueuedScan(
      lid: '${purpose == 'boarding' ? 'b' : 'a'}-${DateTime.now().microsecondsSinceEpoch}',
      purpose: purpose,
      qr: qr,
      scannedAt: scannedAt,
      tripLegId: tripLegId,
      tripId: tripId,
      childIds: childIds,
      allowOutsider: allowOutsider,
      itineraryId: itineraryId,
      stopId: stopId,
      label: label,
    );
    await _saveQueue([...items, item]);
    return item;
  }

  /// Quita de la lista los ya enviados (todo lo que no está pendiente).
  static Future<void> clearSent() async => _saveQueue((await queue()).where((i) => i.pending).toList());

  static Future<void> remove(String lid) async => _saveQueue((await queue()).where((i) => i.lid != lid).toList());

  /// Reenvía uno rechazado (p. ej. tras confirmar a alguien de fuera).
  static Future<void> retry(String lid, {bool? allowOutsider}) async {
    final items = await queue();
    await _saveQueue([
      for (final i in items)
        if (i.lid == lid)
          QueuedScan.fromJson({...i.toJson(), 'status': 'pending', 'code': null, 'detail': null, 'allowOutsider': ?allowOutsider})
        else
          i,
    ]);
  }

  /// Envía los pendientes con POST /offline-scans (de 200 en 200) y guarda
  /// el resultado de cada uno. Devuelve los que tenían resultado nuevo.
  static Future<List<QueuedScan>> flush(ApiClient api) async {
    var items = await queue();
    final pending = items.where((i) => i.pending).toList();
    final results = <QueuedScan>[];
    for (var start = 0; start < pending.length; start += 200) {
      final batch = pending.sublist(start, start + 200 > pending.length ? pending.length : start + 200);
      final document = await api.post('/offline-scans', {'data': [for (final i in batch) i.toRequest()]});
      final byId = {for (final r in document.resources) r.id: r};
      items = await queue();
      for (var k = 0; k < items.length; k++) {
        final r = byId[items[k].lid];
        if (r == null) continue;
        items[k] = items[k].withResult(r.string('status') ?? 'rejected', r.string('code'), r.string('detail'));
        results.add(items[k]);
      }
      await _saveQueue(items);
    }
    return results;
  }
}

class LegBoardings {
  final Set<String> userIds;
  final Set<String> printedUserIds;
  final Set<String> childIds;

  const LegBoardings({this.userIds = const {}, this.printedUserIds = const {}, this.childIds = const {}});

  factory LegBoardings.fromJson(Map<String, dynamic> j) => LegBoardings(
        userIds: {for (final id in (j['users'] as List? ?? const [])) '$id'},
        printedUserIds: {for (final id in (j['printed'] as List? ?? const [])) '$id'},
        childIds: {for (final id in (j['children'] as List? ?? const [])) '$id'},
      );
}

/// Sincronización de lo necesario para escanear sin conexión (la llama
/// SyncService con la parte de viajes): clave del servidor, listas de las
/// Entidades en las que puede escanear y envío de la cola.
abstract final class QrSync {
  static const _scanOperations = [Op.trackingScanBoarding, Op.membersAssignByQr, Op.trackingDrive];

  /// Entidades cuya lista hay que tener. [me] es lo que guarda SyncService.rememberMe.
  static Future<Set<String>> scanEntities(ApiClient api, Map<String, dynamic> me) async {
    final permissions = Permissions.fromJson(me['permissions'] as List?, isAdmin: me['isAdmin'] == true);
    final entities = <String>{};
    var all = false;
    for (final op in _scanOperations) {
      final set = permissions.entitiesFor(op);
      if (set == null) {
        all = true;
      } else {
        entities.addAll(set);
      }
    }
    if (all) {
      // Administrador (o ámbito «todo»): las Entidades activas.
      for (final r in await api.getAll('/entities')) {
        if (r.attributes['active'] != false) entities.add(r.id);
      }
    }
    return entities;
  }

  static Future<void> run(ApiClient api, Map<String, dynamic> me) async {
    try {
      final key = await api.get('/qr-public-key');
      final value = key.resource.string('publicKey');
      if (value != null) await QrStore.setServerPublicKey(value);
    } catch (_) {
      // Sin conexión: se queda la guardada.
    }
    try {
      await QrStore.flush(api);
    } catch (_) {
      // Se reintenta en la próxima sincronización.
    }
    final Set<String> entities;
    try {
      entities = await scanEntities(api, me);
    } catch (_) {
      return;
    }
    for (final entityId in entities.take(30)) {
      try {
        final roster = await api.get('/entities/$entityId/scan-roster');
        final attributes = roster.resource.attributes;
        await QrStore.saveRoster(entityId, attributes);
        final key = attributes['serverPublicKey'] as String?;
        if (key != null) await QrStore.setServerPublicKey(key);
      } on ApiException catch (_) {
        // Sin permiso en esa Entidad o sin conexión: se mantiene la anterior.
      }
    }
  }
}
