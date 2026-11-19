import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitransporte/core/formats.dart';
import 'package:mitransporte/core/units.dart';

void main() {
  test('tiempos con unidades combinables (docs/11 §11.40)', () {
    expect(parseDuration('10min'), const Duration(minutes: 10));
    expect(parseDuration('12hor30min30seg'), const Duration(hours: 12, minutes: 30, seconds: 30));
    expect(parseDuration('1mes'), const Duration(days: 30));
    expect(parseDuration('1ano6mes'), const Duration(days: 365 + 180));
    expect(parseDuration('2sem3dia'), const Duration(days: 17));
    expect(parseDuration('10'), const Duration(seconds: 10));
    expect(parseDuration('10xyz'), isNull);
    expect(parseDuration(''), isNull);
  });

  test('distancias y velocidades', () {
    expect(parseDistance('100m'), 100);
    expect(parseDistance('1km200m'), 1200);
    expect(parseDistance('1km'), 1000);
    expect(parseSpeed('10km/hor'), closeTo(2.7778, 0.001));
    expect(parseSpeed('200m/min'), closeTo(3.3333, 0.001));
    expect(parseSpeed('10km'), isNull);
  });

  test('fechas «Sáb. 07/11/26» y horas de 24 h, como en las notificaciones (docs/11 §11.67)', () async {
    await initializeDateFormatting('es');
    expect(formatDate(DateTime(2026, 11, 7)), 'Sáb. 07/11/26');
    expect(formatDate(DateTime(2026, 11, 9)), 'Lun. 09/11/26');
    expect(formatTime(DateTime(2026, 11, 7, 17, 5)), '17:05');
    expect(formatTime(DateTime(2026, 11, 7, 0, 30)), '00:30');
    expect(formatDateTime(DateTime(2026, 11, 19, 10, 30)), 'Jue. 19/11/26 10:30');
    expect(formatDayTime(DateTime(2026, 11, 19), '07:05'), 'Jue. 19/11/26 07:05');
    expect(hhmm24('6:00'), '06:00');
    expect(apiDay(DateTime(2026, 1, 2)), '2026-01-02');
    expect(parseDay('2026-03-14'), DateTime(2026, 3, 14));
    expect(plural(1, 'asiento', 'asientos'), '1 asiento');
    expect(plural(3, 'asiento', 'asientos'), '3 asientos');
  });
}
