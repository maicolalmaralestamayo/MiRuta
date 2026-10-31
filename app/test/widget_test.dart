import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/password_policy.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/services/app_pin.dart';
import 'package:mitransporte/services/notifications.dart';
import 'package:mitransporte/services/templates.dart';
import 'package:mitransporte/services/user_settings.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Momento del aviso (7.16)', () {
    final event = DateTime(2026, 11, 3, 17, 0);

    test('tiempo antes', () {
      final settings = UserSettings({'departure_notice_mode': 'relative', 'departure_notice_minutes_before': '45'});
      expect(Notifications.noticeTime(event, 'departure', settings), DateTime(2026, 11, 3, 16, 15));
    });

    test('hora fija del día anterior', () {
      final settings = UserSettings({'return_notice_mode': 'fixed', 'return_notice_fixed_time': '23:00', 'return_notice_fixed_days_before': '1'});
      expect(Notifications.noticeTime(event, 'return', settings), DateTime(2026, 11, 2, 23, 0));
    });

    test('hora fija que cae después del viaje', () {
      final fallback = UserSettings({'departure_notice_mode': 'fixed', 'departure_notice_fixed_time': '18:00', 'departure_notice_fixed_days_before': '0'});
      expect(Notifications.noticeTime(event, 'departure', fallback), DateTime(2026, 11, 3, 16, 0));
      final none = UserSettings({...fallback.values, 'departure_notice_fallback': 'none'});
      expect(Notifications.noticeTime(event, 'departure', none), isNull);
    });
  });

  test('textos de aviso con variables', () {
    expect(renderTemplate('Pasó por {parada}. Faltan {paradas_restantes}. {desconocida}', {'parada': 'Empresa', 'paradas_restantes': '2'}),
        'Pasó por Empresa. Faltan 2. {desconocida}');
  });

  test('documento JSON:API con recursos incluidos', () {
    final document = JsonApiDocument.fromJson({
      'data': {
        'type': 'workers', 'id': '1', 'attributes': {'firstName': 'Ana'},
        'relationships': {'rank': {'data': {'type': 'ranks', 'id': '17'}}},
      },
      'included': [
        {'type': 'ranks', 'id': '17', 'attributes': {'name': 'Trabajador civil'}},
      ],
    });
    expect(document.resource.string('firstName'), 'Ana');
    expect(document.resource.related('rank')!.string('name'), 'Trabajador civil');
  });

  test('formato del PIN de la app', () {
    expect(AppPin.isValidFormat('1234'), isTrue);
    expect(AppPin.isValidFormat('123456'), isTrue);
    expect(AppPin.isValidFormat('123'), isFalse);
    expect(AppPin.isValidFormat('1234567'), isFalse);
    expect(AppPin.isValidFormat('12a4'), isFalse);
  });

  test('PIN con PBKDF2 (vector de prueba del RFC 7914)', () {
    // PBKDF2-HMAC-SHA256, P = "passwd", S = "salt", c = 1, 32 bytes.
    expect(AppPin.pbkdf2('passwd', 'salt', 1), 'VawEblbjCJ/sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=');
    // Mismo resultado que hashlib.pbkdf2_hmac de Python con 1000 iteraciones.
    expect(AppPin.pbkdf2('1234', 'c2FsdA==', 1000), '4KyVPjWH6bj+MdRc5m0u1mb/h6rSzx6bJMY9N05G28w=');
  });

  test('requisitos de la contraseña', () {
    const policy = PasswordPolicy(minLength: 8, requiredClasses: 3);
    expect(policy.validate('corta1A'), isNotNull);
    expect(policy.validate('solominusculas'), isNotNull);
    expect(policy.validate('Viaje.2026'), isNull);
    expect(policy.validate('Maicol.2026', personal: ['maicol']), isNotNull);
    expect(PasswordPolicy.classCount('aA1.'), 4);
  });
}
