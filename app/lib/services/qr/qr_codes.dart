/// Códigos QR de MiRuta 3.0 (docs/11 §11.8 y §11.9; V3-PARTE-B §1): formato,
/// codificaciones y verificación SIN conexión en el teléfono que escanea.
///
/// - Segmentos: base64url sin relleno. Claves: SPKI DER en base64 estándar.
/// - Firmas: ECDSA P-256 con SHA-256 en DER, sobre los bytes JSON exactos del
///   segmento (no se vuelve a serializar el JSON).
/// - `MR1.<J>.<firmaServidor(J)>.<P>.<firmaTeléfono(P)>` (dinámico, teléfono).
/// - `MRP1.<J>.<firmaServidor(J)>` (impreso, sin teléfono).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Diferencia de hora admitida entre los dos teléfonos (±2 min).
const qrClockSkewSeconds = 120;

/// Cada cuánto se renueva el QR en pantalla.
const qrRefreshSeconds = 15;

enum QrKind { dynamic, printed }

/// Error de verificación con el mismo código que la API.
class QrException implements Exception {
  final String code;
  final String message;

  const QrException(this.code, this.message);

  static const invalid = QrException('QR_INVALID', 'El código QR no es de MiRuta o está dañado.');

  @override
  String toString() => 'QrException($code): $message';
}

/// Resultado de una verificación correcta.
class QrCheck {
  final QrKind kind;
  final int userId;

  /// Solo en el dinámico.
  final String? nonce;
  final DateTime? issuedAt;

  /// Versión del impreso.
  final int? printedVersion;

  const QrCheck({required this.kind, required this.userId, this.nonce, this.issuedAt, this.printedVersion});

  /// Clave del código para «ya usado» (dinámico: persona + nonce).
  String? get nonceKey => nonce == null ? null : '$userId:$nonce';
}

// ---------------------------------------------------------------------------
// Codificaciones
// ---------------------------------------------------------------------------

String base64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List? base64UrlDecodeStrict(String text) {
  if (text.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) return null;
  try {
    return base64Url.decode(text + '=' * ((4 - text.length % 4) % 4));
  } catch (_) {
    return null;
  }
}

/// Cabecera SPKI DER de una clave pública EC P-256 sin comprimir (26 bytes);
/// le siguen los 65 bytes del punto (04 ‖ X ‖ Y).
final _p256SpkiHeader = Uint8List.fromList(const [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, //
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
]);

final ECDomainParameters _p256 = ECCurve_secp256r1();

/// Clave pública P-256 desde SPKI DER (base64 estándar). null si no lo es.
ECPublicKey? publicKeyFromSpki(String base64Spki) {
  Uint8List der;
  try {
    der = base64.decode(base64Spki.trim());
  } catch (_) {
    return null;
  }
  if (der.length != _p256SpkiHeader.length + 65 || der[_p256SpkiHeader.length] != 0x04) return null;
  for (var i = 0; i < _p256SpkiHeader.length; i++) {
    if (der[i] != _p256SpkiHeader[i]) return null;
  }
  try {
    final point = _p256.curve.decodePoint(der.sublist(_p256SpkiHeader.length));
    return point == null ? null : ECPublicKey(point, _p256);
  } catch (_) {
    return null;
  }
}

/// SPKI DER (base64 estándar) de una clave pública P-256.
String spkiFromPublicKey(ECPublicKey key) => base64.encode([..._p256SpkiHeader, ...key.Q!.getEncoded(false)]);

BigInt _bigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

List<int> _derInteger(BigInt value) {
  final bytes = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    bytes.insert(0, (v & BigInt.from(0xff)).toInt());
    v >>= 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return [0x02, bytes.length, ...bytes];
}

/// Firma ECDSA en DER (`SEQUENCE{INTEGER r, INTEGER s}`).
Uint8List encodeDerSignature(ECSignature signature) {
  final body = [..._derInteger(signature.r), ..._derInteger(signature.s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

/// Lee una firma ECDSA en DER. null si no lo es (p. ej. r‖s de 64 bytes).
ECSignature? decodeDerSignature(List<int> der) {
  if (der.length < 8 || der.length > 80 || der[0] != 0x30 || der[1] != der.length - 2) return null;
  var offset = 2;
  BigInt? readInt() {
    if (offset + 2 > der.length || der[offset] != 0x02) return null;
    final length = der[offset + 1];
    if (length == 0 || length > 33 || offset + 2 + length > der.length) return null;
    final value = _bigInt(der.sublist(offset + 2, offset + 2 + length));
    offset += 2 + length;
    return value;
  }

  final r = readInt();
  final s = readInt();
  if (r == null || s == null || offset != der.length || r <= BigInt.zero || s <= BigInt.zero) return null;
  return ECSignature(r, s);
}

/// Verifica una firma ECDSA P-256 SHA-256 (DER) sobre [bytes].
bool verifyEcdsa(ECPublicKey key, List<int> bytes, List<int> derSignature) {
  final signature = decodeDerSignature(derSignature);
  if (signature == null) return false;
  try {
    final signer = ECDSASigner(SHA256Digest())..init(false, PublicKeyParameter<ECPublicKey>(key));
    return signer.verifySignature(Uint8List.fromList(bytes), signature);
  } catch (_) {
    return false;
  }
}

/// Firma ECDSA P-256 SHA-256 en DER con una clave en memoria (pruebas; el
/// teléfono firma con el Android Keystore).
Uint8List signEcdsa(ECPrivateKey key, List<int> bytes, {Random? random}) {
  final secure = FortunaRandom();
  final rnd = random ?? Random.secure();
  secure.seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)))));
  final signer = ECDSASigner(SHA256Digest())..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(key), secure));
  return encodeDerSignature(signer.generateSignature(Uint8List.fromList(bytes)) as ECSignature);
}

/// Par de claves P-256 en memoria (pruebas).
AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateP256KeyPair() {
  final rnd = Random.secure();
  final secure = FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)))));
  final generator = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_p256), secure));
  return generator.generateKeyPair();
}

// ---------------------------------------------------------------------------
// Generación (teléfono que muestra el QR)
// ---------------------------------------------------------------------------

/// Nonce de 8 bytes aleatorios en hexadecimal en minúsculas.
String newQrNonce([Random? random]) {
  final rnd = random ?? Random.secure();
  return List.generate(8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Bytes JSON del payload `{"u":…,"t":…,"n":"…"}` (enteros, sin espacios).
Uint8List qrPayloadBytes(int userId, DateTime now, String nonce) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'u': userId, 't': now.millisecondsSinceEpoch ~/ 1000, 'n': nonce})));

/// Texto del QR dinámico: `MR1.<certificado>.<payload>.<firma>`.
String buildDynamicQr(String certificate, List<int> payload, List<int> derSignature) =>
    'MR1.$certificate.${base64UrlNoPad(payload)}.${base64UrlNoPad(derSignature)}';

/// Datos del certificado del teléfono (`{"u","k","e","v"}`), sin comprobar la firma.
class QrCertificate {
  final int userId;
  final String publicKey;
  final DateTime expiresAt;

  const QrCertificate(this.userId, this.publicKey, this.expiresAt);

  static QrCertificate? parse(String certificate) {
    final parts = certificate.split('.');
    if (parts.length != 2) return null;
    final bytes = base64UrlDecodeStrict(parts[0]);
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['u'] is! int || json['k'] is! String || json['e'] is! int) return null;
      return QrCertificate(json['u'] as int, json['k'] as String, DateTime.fromMillisecondsSinceEpoch((json['e'] as int) * 1000));
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Verificación (teléfono que escanea)
// ---------------------------------------------------------------------------

Map<String, dynamic>? _json(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, dynamic> ? value : null;
  } catch (_) {
    return null;
  }
}

/// Verifica un QR sin conexión (V3-PARTE-B §1, pasos 1–7 del MR1 y 1–2 del MRP1).
///
/// - [serverPublicKey]: SPKI base64 guardada al sincronizar.
/// - [now]: hora del teléfono que escanea.
/// - [isNonceUsed]: el código ya se usó en este teléfono.
/// - [printedVersionOf]: versión vigente del impreso de esa persona según la
///   lista sin conexión (`printedQrVersion`); null = usa el teléfono (anulado).
///   Si la persona no está en la lista, `notInRoster` (se deja pasar: el
///   servidor lo resuelve al sincronizar).
QrCheck verifyQr(
  String text, {
  required String serverPublicKey,
  required DateTime now,
  bool Function(int userId, String nonce)? isNonceUsed,
  ({bool inRoster, int? version}) Function(int userId)? printedVersionOf,
}) {
  final parts = text.trim().split('.');
  final server = publicKeyFromSpki(serverPublicKey);
  if (server == null) throw const QrException('QR_NO_SERVER_KEY', 'Falta la clave del servidor: sincronice con conexión al menos una vez.');
  final seconds = now.millisecondsSinceEpoch ~/ 1000;

  if (parts.length == 5 && parts[0] == 'MR1') {
    final j = base64UrlDecodeStrict(parts[1]);
    final sigJ = base64UrlDecodeStrict(parts[2]);
    final p = base64UrlDecodeStrict(parts[3]);
    final sigP = base64UrlDecodeStrict(parts[4]);
    if (j == null || sigJ == null || p == null || sigP == null) throw QrException.invalid;
    final certificate = _json(j);
    final payload = _json(p);
    if (certificate == null ||
        payload == null ||
        certificate['u'] is! int ||
        certificate['k'] is! String ||
        certificate['e'] is! int ||
        certificate['v'] == null ||
        payload['u'] is! int ||
        payload['t'] is! int ||
        payload['n'] is! String ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(payload['n'] as String)) {
      throw QrException.invalid;
    }
    if (!verifyEcdsa(server, j, sigJ)) {
      throw const QrException('QR_CERTIFICATE_INVALID', 'El certificado del teléfono no lo firmó este servidor.');
    }
    if (certificate['u'] != payload['u']) {
      throw const QrException('QR_CERTIFICATE_INVALID', 'El certificado del teléfono es de otra persona.');
    }
    if ((certificate['e'] as int) < seconds) {
      throw const QrException('QR_CERTIFICATE_EXPIRED', 'El certificado del teléfono caducó. La persona debe abrir la app con conexión para renovarlo.');
    }
    final device = publicKeyFromSpki(certificate['k'] as String);
    if (device == null || !verifyEcdsa(device, p, sigP)) {
      throw const QrException('QR_SIGNATURE_INVALID', 'La firma del código QR no es válida.');
    }
    final t = payload['t'] as int;
    if ((t - seconds).abs() > qrClockSkewSeconds) {
      throw const QrException('QR_EXPIRED', 'El código QR caducó (o la hora de los teléfonos difiere en más de 2 minutos). Pida que lo muestre de nuevo.');
    }
    final userId = payload['u'] as int;
    final nonce = payload['n'] as String;
    if (isNonceUsed != null && isNonceUsed(userId, nonce)) {
      throw const QrException('QR_ALREADY_USED', 'Este código QR ya se usó. Cada código vale una sola vez: pida que lo muestre de nuevo.');
    }
    return QrCheck(kind: QrKind.dynamic, userId: userId, nonce: nonce, issuedAt: DateTime.fromMillisecondsSinceEpoch(t * 1000));
  }

  if (parts.length == 3 && parts[0] == 'MRP1') {
    final j = base64UrlDecodeStrict(parts[1]);
    final sig = base64UrlDecodeStrict(parts[2]);
    if (j == null || sig == null) throw QrException.invalid;
    final json = _json(j);
    if (json == null || json['u'] is! int || json['v'] is! int) throw QrException.invalid;
    if (!verifyEcdsa(server, j, sig)) throw const QrException('QR_SIGNATURE_INVALID', 'La firma del código QR no es válida.');
    final userId = json['u'] as int;
    final version = json['v'] as int;
    final known = printedVersionOf?.call(userId);
    if (known != null && known.inRoster && known.version != version) {
      throw const QrException('QR_REVOKED', 'Este QR impreso fue anulado. Si la persona usa la app, debe mostrar el QR de su teléfono.');
    }
    return QrCheck(kind: QrKind.printed, userId: userId, printedVersion: version);
  }

  throw QrException.invalid;
}
