import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import 'qr_codes.dart';

/// «Incluir por QR» sin conexión (docs/11 §11.19 y §11.27; docs/13 §13.9):
/// el teléfono que escanea comprueba el QR con la clave del servidor, guarda
/// la inclusión con la hora del escaneo y la envía al volver la conexión
/// (hasta 7 días).
class QrQueue {
  static const _serverKey = 'user.qr.server_key';
  static const _queueKey = 'user.qr.inclusions';
  static const _noncesKey = 'user.qr.nonces';
  static const maxDays = 7;

  static Future<String?> serverPublicKey() => Storage.getString(_serverKey);

  /// Descarga la clave pública del servidor (para comprobar sin conexión).
  static Future<void> refreshServerKey(ApiClient api) async {
    final document = await api.get('/qr-public-key');
    final key = document.resource.string('publicKey');
    if (key != null) await Storage.setString(_serverKey, key);
  }

  /// Comprueba el QR sin conexión y devuelve la persona (su id).
  static Future<QrCheck> verify(String qr) async {
    final key = await serverPublicKey();
    if (key == null) throw const QrException('QR_NO_SERVER_KEY', 'Para incluir sin conexión, abra antes la app con conexión una vez.');
    final used = (await Storage.getJson(_noncesKey)).keys.toSet();
    return verifyQr(qr, serverPublicKey: key, now: DateTime.now(), isNonceUsed: (u, n) => used.contains('$u:$n'));
  }

  static Future<List<Map<String, dynamic>>> pending() async {
    final json = await Storage.getJson(_queueKey);
    final limit = DateTime.now().subtract(const Duration(days: maxDays));
    return [
      for (final item in (json['items'] as List? ?? const []))
        if (DateTime.tryParse('${(item as Map)['scannedAt']}')?.isAfter(limit) ?? false) Map<String, dynamic>.from(item),
    ];
  }

  /// Guarda una inclusión para enviarla después.
  static Future<void> enqueue({required String qr, required QrCheck check, required String label, String? entityId, String? itineraryId, String? stopId}) async {
    final items = await pending();
    items.add({
      'qr': qr,
      'scannedAt': DateTime.now().toIso8601String(),
      'label': label,
      'entityId': ?entityId,
      'itineraryId': ?itineraryId,
      'stopId': ?stopId,
    });
    await Storage.setJson(_queueKey, {'items': items});
    final nonces = await Storage.getJson(_noncesKey);
    if (check.nonceKey != null) nonces[check.nonceKey!] = DateTime.now().toIso8601String();
    await Storage.setJson(_noncesKey, nonces);
  }

  /// Cuerpo de POST qr-inclusions.
  static Map<String, dynamic> body({required String qr, DateTime? scannedAt, String? entityId, String? itineraryId, String? stopId}) =>
      resourceData('qr-inclusions', attributes: {
        'qr': qr,
        if (scannedAt != null) 'scannedAt': scannedAt.toIso8601String(),
      }, relationships: {
        if (entityId != null) 'entity': ResourceId('entities', entityId),
        if (itineraryId != null) 'itinerary': ResourceId('itineraries', itineraryId),
        if (stopId != null) 'stop': ResourceId('stops', stopId),
      });

  /// Envía las pendientes. Devuelve los textos de las que fallaron.
  static Future<List<String>> flush(ApiClient api) async {
    final items = await pending();
    if (items.isEmpty) return const [];
    final failed = <String>[];
    final keep = <Map<String, dynamic>>[];
    for (final item in items) {
      try {
        await api.post('/qr-inclusions', body(
          qr: '${item['qr']}',
          scannedAt: DateTime.tryParse('${item['scannedAt']}'),
          entityId: item['entityId'] as String?,
          itineraryId: item['itineraryId'] as String?,
          stopId: item['stopId'] as String?,
        ));
      } on ApiException catch (error) {
        if (error.isNetwork || (error.statusCode ?? 0) >= 500) {
          keep.add(item);
        } else {
          failed.add('${item['label']}: ${error.message}');
        }
      }
    }
    await Storage.setJson(_queueKey, {'items': keep});
    return failed;
  }
}
