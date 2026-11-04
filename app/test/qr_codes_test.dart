import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/services/qr/qr_codes.dart';

/// Vectores generados con OpenSSL (la misma biblioteca que usa la API en
/// api/app/Services/QrCodes.php: openssl_sign con OPENSSL_ALGO_SHA256, firma
/// DER, claves SPKI DER en base64), con el formato exacto de V3-PARTE-B §1.
const serverKey =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXahlivW880kYMKqmY9qidwl+F0ETVBScOmUMteNgyo0dL3HhvpD17RoV/eaD2B+qN2d8hmarnHxyOewSs89EBQ==';
const deviceKey =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEX6x/t+D46nQ0IlhStcx3k7iLOvga9RS1I2PD+5on9xit+s8JIjww4CNeqWujC/PfoslWerzFeKYkqruqDeS6VA==';

/// Certificado {"u":12,"k":deviceKey,"e":1765000000,"v":1} y payload {"u":12,"t":1764000000,"n":"a1b2c3d4e5f60718"}.
const certificate =
    'eyJ1IjoxMiwiayI6Ik1Ga3dFd1lIS29aSXpqMENBUVlJS29aSXpqMERBUWNEUWdBRVg2eC90K0Q0Nm5RMElsaFN0Y3gzazdpTE92Z2E5UlMxSTJQRCs1b245eGl0K3M4Sklqd3c0Q05lcVd1akMvUGZvc2xXZXJ6RmVLWWtxcnVxRGVTNlZBPT0iLCJlIjoxNzY1MDAwMDAwLCJ2IjoxfQ'
    '.MEUCIQC52n-P7rR32mJITmT9sqGaw_mWjMXlDF6hQqerGF0reQIgPp7xNrigIYpkyLUPdckK3lGSowI0_5ImjdoE2_H9C68';
const payload = 'eyJ1IjoxMiwidCI6MTc2NDAwMDAwMCwibiI6ImExYjJjM2Q0ZTVmNjA3MTgifQ';
const payloadSignature = 'MEUCIQDeRuvxDFnahKOzkIvIvylg0IAzBNQopu_1MEsB4Ab1KQIgVXmB7OcfwCFOhWaOSZy3ar0yPaqsnnxmT60i_kao12Y';
const dynamicQr = 'MR1.$certificate.$payload.$payloadSignature';

/// Impreso {"u":30,"v":2}.
const printedQr =
    'MRP1.eyJ1IjozMCwidiI6Mn0.MEUCIFGFUMfvOGvD_a6Wk7FXNhVMvDquSt4EWsCAGeS6aa-oAiEAhxYN3TCEnM1lpViTnHPyITL7qz880m16yajJ2dCO3iw';

final issuedAt = DateTime.fromMillisecondsSinceEpoch(1764000000 * 1000);

String codeOf(void Function() action) {
  try {
    action();
  } on QrException catch (error) {
    return error.code;
  }
  return 'OK';
}

QrCheck verify(String qr, {DateTime? now, bool Function(int, String)? used, ({bool inRoster, int? version}) Function(int)? printed, String key = serverKey}) =>
    verifyQr(qr, serverPublicKey: key, now: now ?? issuedAt, isNonceUsed: used, printedVersionOf: printed);

void main() {
  group('Vectores de la API (OpenSSL)', () {
    test('MR1 válido', () {
      final check = verify(dynamicQr);
      expect(check.kind, QrKind.dynamic);
      expect(check.userId, 12);
      expect(check.nonce, 'a1b2c3d4e5f60718');
      expect(check.nonceKey, '12:a1b2c3d4e5f60718');
      expect(check.issuedAt, issuedAt);
    });

    test('±120 s de diferencia de hora', () {
      expect(codeOf(() => verify(dynamicQr, now: issuedAt.add(const Duration(seconds: 120)))), 'OK');
      expect(codeOf(() => verify(dynamicQr, now: issuedAt.subtract(const Duration(seconds: 120)))), 'OK');
      expect(codeOf(() => verify(dynamicQr, now: issuedAt.add(const Duration(seconds: 121)))), 'QR_EXPIRED');
      expect(codeOf(() => verify(dynamicQr, now: issuedAt.subtract(const Duration(seconds: 121)))), 'QR_EXPIRED');
    });

    test('certificado caducado', () {
      expect(codeOf(() => verify(dynamicQr, now: DateTime.fromMillisecondsSinceEpoch(1765000001 * 1000))), 'QR_CERTIFICATE_EXPIRED');
    });

    test('código ya usado en este teléfono', () {
      expect(codeOf(() => verify(dynamicQr, used: (u, n) => u == 12 && n == 'a1b2c3d4e5f60718')), 'QR_ALREADY_USED');
      expect(codeOf(() => verify(dynamicQr, used: (u, n) => false)), 'OK');
    });

    test('certificado de otro servidor', () {
      final other = spkiFromPublicKey(generateP256KeyPair().publicKey);
      expect(codeOf(() => verify(dynamicQr, key: other)), 'QR_CERTIFICATE_INVALID');
      expect(codeOf(() => verify(printedQr, key: other)), 'QR_SIGNATURE_INVALID');
    });

    test('payload o firma del teléfono manipulados', () {
      final forged = base64UrlNoPad(utf8.encode('{"u":12,"t":1764000000,"n":"ffffffffffffffff"}'));
      expect(codeOf(() => verify('MR1.$certificate.$forged.$payloadSignature')), 'QR_SIGNATURE_INVALID');
      final otherUser = base64UrlNoPad(utf8.encode('{"u":13,"t":1764000000,"n":"a1b2c3d4e5f60718"}'));
      expect(codeOf(() => verify('MR1.$certificate.$otherUser.$payloadSignature')), 'QR_CERTIFICATE_INVALID');
      expect(codeOf(() => verify('MR1.$certificate.$payload.${payloadSignature.substring(0, 20)}AAAA')), 'QR_SIGNATURE_INVALID');
    });

    test('MRP1 válido y anulado', () {
      final check = verify(printedQr, printed: (u) => (inRoster: true, version: 2));
      expect(check.kind, QrKind.printed);
      expect(check.userId, 30);
      expect(check.printedVersion, 2);
      // Versión distinta o usa el teléfono (null): anulado.
      expect(codeOf(() => verify(printedQr, printed: (u) => (inRoster: true, version: 3))), 'QR_REVOKED');
      expect(codeOf(() => verify(printedQr, printed: (u) => (inRoster: true, version: null))), 'QR_REVOKED');
      // No está en la lista (otra Entidad o alta posterior): lo resuelve el servidor.
      expect(codeOf(() => verify(printedQr, printed: (u) => (inRoster: false, version: null))), 'OK');
    });

    test('QR que no es de MiRuta', () {
      for (final text in ['hola', 'MR1.a.b', 'MRP1.a.b.c', 'MR2.$certificate.$payload.$payloadSignature', 'MR1.$certificate.$payload.\$\$\$', 'MRP1.e30.MEUC']) {
        expect(codeOf(() => verify(text)), anyOf('QR_INVALID', 'QR_SIGNATURE_INVALID'), reason: text);
      }
      expect(codeOf(() => verify('MRP1.e30.MEUC')), 'QR_INVALID');
    });

    test('lee el certificado', () {
      final parsed = QrCertificate.parse(certificate)!;
      expect(parsed.userId, 12);
      expect(parsed.publicKey, deviceKey);
      expect(parsed.expiresAt, DateTime.fromMillisecondsSinceEpoch(1765000000 * 1000));
      expect(publicKeyFromSpki(deviceKey), isNotNull);
      expect(spkiFromPublicKey(publicKeyFromSpki(deviceKey)!), deviceKey);
    });
  });

  group('Generado en Dart', () {
    test('QR dinámico firmado en el teléfono y verificado', () {
      final server = generateP256KeyPair();
      final device = generateP256KeyPair();
      final serverSpki = spkiFromPublicKey(server.publicKey);
      final j = utf8.encode(jsonEncode({'u': 7, 'k': spkiFromPublicKey(device.publicKey), 'e': 1800000000, 'v': 1}));
      final cert = '${base64UrlNoPad(j)}.${base64UrlNoPad(signEcdsa(server.privateKey, j))}';
      final now = DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000);
      final nonce = newQrNonce();
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(nonce), isTrue);
      final p = qrPayloadBytes(7, now, nonce);
      expect(utf8.decode(p), '{"u":7,"t":1790000000,"n":"$nonce"}');
      final qr = buildDynamicQr(cert, p, signEcdsa(device.privateKey, p));
      expect(qr.split('.'), hasLength(5));
      final check = verifyQr(qr, serverPublicKey: serverSpki, now: now.add(const Duration(seconds: 30)));
      expect(check.userId, 7);
      expect(check.nonce, nonce);
      // Firmado con otra clave del teléfono (copia de la app sin la clave).
      final copy = buildDynamicQr(cert, p, signEcdsa(generateP256KeyPair().privateKey, p));
      expect(codeOf(() => verifyQr(copy, serverPublicKey: serverSpki, now: now)), 'QR_SIGNATURE_INVALID');
    });

    test('firma DER', () {
      final pair = generateP256KeyPair();
      for (var i = 0; i < 20; i++) {
        final bytes = utf8.encode('mensaje $i');
        final der = signEcdsa(pair.privateKey, bytes);
        expect(der[0], 0x30);
        expect(der.length, inInclusiveRange(68, 72));
        final decoded = decodeDerSignature(der)!;
        expect(encodeDerSignature(decoded), der);
        expect(verifyEcdsa(pair.publicKey, bytes, der), isTrue);
        expect(verifyEcdsa(pair.publicKey, utf8.encode('otro'), der), isFalse);
      }
      // r‖s de 64 bytes no es DER.
      expect(decodeDerSignature(List.filled(64, 1)), isNull);
    });
  });
}
