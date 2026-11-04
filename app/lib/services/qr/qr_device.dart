import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/json_api.dart';
import '../../core/storage.dart';
import 'qr_codes.dart';

/// Clave del teléfono para el QR (docs/11 §11.8): par ECDSA P-256 en el
/// Android Keystore (no exportable), por el canal `mitransporte/qr` de
/// MainActivity.kt. También activa FLAG_SECURE en la pantalla del QR.
abstract final class QrDevice {
  static const _channel = MethodChannel('mitransporte/qr');
  static const _certificateKey = 'user.qr.certificate';

  /// Se renueva cuando le quedan menos días que estos (caduca a los 30).
  static const renewBeforeDays = 7;

  /// Clave pública SPKI DER en base64 (la crea si no existe).
  static Future<String> publicKey() async => (await _channel.invokeMethod<String>('publicKey'))!;

  /// Firma ECDSA P-256 SHA-256 (DER) de [bytes] con la clave del Keystore.
  static Future<Uint8List> sign(Uint8List bytes) async => (await _channel.invokeMethod<Uint8List>('sign', bytes))!;

  /// FLAG_SECURE: sin capturas ni grabación de pantalla.
  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('secure', secure);
    } on MissingPluginException {
      // Fuera de Android (pruebas).
    }
  }

  /// Certificado guardado: `{certificate, expiresAt, userId, publicKey}`.
  static Future<StoredCertificate?> certificate() async {
    final json = await Storage.getJson(_certificateKey);
    if (json['certificate'] == null) return null;
    return StoredCertificate(
      certificate: '${json['certificate']}',
      expiresAt: DateTime.parse('${json['expiresAt']}').toLocal(),
      userId: '${json['userId']}',
      publicKey: '${json['publicKey']}',
    );
  }

  /// Registra la clave con POST /me/qr-devices si no hay certificado, es de
  /// otra persona o de otra clave, o le quedan menos de [renewBeforeDays].
  /// Lanza el error si no se pudo y no hay uno válido.
  static Future<StoredCertificate> ensureCertificate(ApiClient api, String userId, {bool force = false}) async {
    final key = await publicKey();
    final current = await certificate();
    final fresh = current != null &&
        current.userId == userId &&
        current.publicKey == key &&
        current.expiresAt.isAfter(DateTime.now().add(const Duration(days: renewBeforeDays)));
    if (fresh && !force) return current;
    try {
      final document = await api.post('/me/qr-devices', resourceData('qr-devices', attributes: {'publicKey': key}));
      final r = document.resource;
      final certificate = r.string('certificate')!;
      final parsed = QrCertificate.parse(certificate);
      final stored = StoredCertificate(
        certificate: certificate,
        expiresAt: parsed?.expiresAt ?? r.date('expiresAt') ?? DateTime.now().add(const Duration(days: 30)),
        userId: userId,
        publicKey: key,
      );
      await Storage.setJson(_certificateKey, {
        'certificate': stored.certificate,
        'expiresAt': stored.expiresAt.toUtc().toIso8601String(),
        'userId': userId,
        'publicKey': key,
      });
      return stored;
    } catch (_) {
      // Sin conexión: vale el que hay mientras no caduque.
      if (current != null && current.userId == userId && current.publicKey == key && current.expiresAt.isAfter(DateTime.now())) return current;
      rethrow;
    }
  }

  /// Texto del QR dinámico de ahora mismo (sin conexión).
  static Future<String> currentQr(StoredCertificate certificate, {DateTime? now}) async {
    final payload = qrPayloadBytes(int.parse(certificate.userId), now ?? DateTime.now(), newQrNonce());
    final signature = await sign(payload);
    return buildDynamicQr(certificate.certificate, payload, signature);
  }
}

class StoredCertificate {
  final String certificate;
  final DateTime expiresAt;
  final String userId;
  final String publicKey;

  const StoredCertificate({required this.certificate, required this.expiresAt, required this.userId, required this.publicKey});

  bool get expired => !expiresAt.isAfter(DateTime.now());
}
