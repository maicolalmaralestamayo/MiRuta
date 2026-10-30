import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/card_number.dart';
import 'package:mitransporte/core/json_api.dart';
import 'package:mitransporte/services/notifications.dart';
import 'package:mitransporte/services/templates.dart';
import 'package:mitransporte/services/user_settings.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Carné de identidad', () {
    test('ejemplo de la documentación', () {
      final card = CardNumber.tryParse('92071648863')!;
      expect(card.birthDate, DateTime(1992, 7, 16));
      expect(card.sex, 'M');
    });

    test('el séptimo dígito indica el siglo', () {
      expect(CardNumber.tryParse('99123190011')!.birthDate.year, 1899);
      expect(CardNumber.tryParse('85010150011')!.birthDate.year, 1985);
      expect(CardNumber.tryParse('05031560011')!.birthDate.year, 2005);
    });

    test('fechas imposibles o futuras', () {
      expect(CardNumber.isValid('92023048863'), isFalse);
      expect(CardNumber.isValid('01022960011'), isFalse);
      expect(CardNumber.tryParse('26110360011', today: DateTime(2026, 11, 2)), isNull);
      expect(validateCard('123'), isNotNull);
    });

    test('derecho a viajar hasta el 31 de agosto siguiente', () {
      expect(CardNumber.tryParse('11031060011')!.eligibleUntil(16), DateTime(2027, 8, 31));
      expect(CardNumber.tryParse('11101560011')!.eligibleUntil(16), DateTime(2028, 8, 31));
      expect(CardNumber.tryParse('11083160011')!.eligibleUntil(16), DateTime(2027, 8, 31));
      expect(CardNumber.tryParse('12022960011')!.eligibleUntil(16), DateTime(2028, 8, 31));
    });
  });

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
}
