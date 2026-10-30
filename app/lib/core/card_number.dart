/// Carné de identidad de 11 dígitos (docs/07-algoritmos.md §7.1 y §7.9).
class CardNumber {
  final String value;
  final DateTime birthDate;

  CardNumber._(this.value, this.birthDate);

  static CardNumber? tryParse(String? value, {DateTime? today}) {
    if (value == null || !RegExp(r'^\d{11}$').hasMatch(value)) return null;

    final centuryDigit = int.parse(value[6]);
    final century = centuryDigit == 9 ? 1800 : (centuryDigit <= 5 ? 1900 : 2000);
    final year = century + int.parse(value.substring(0, 2));
    final month = int.parse(value.substring(2, 4));
    final day = int.parse(value.substring(4, 6));
    final date = DateTime(year, month, day);

    // DateTime corrige fechas imposibles (30 de febrero → 2 de marzo): se descartan.
    if (date.year != year || date.month != month || date.day != day) return null;
    final now = today ?? DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) return null;

    return CardNumber._(value, date);
  }

  static bool isValid(String? value) => tryParse(value) != null;

  /// Penúltimo dígito: par → masculino, impar → femenino.
  String get sex => int.parse(value[9]).isEven ? 'M' : 'F';

  /// Último día con derecho a viajar: 31 de agosto siguiente al cumpleaños de [maxAge].
  DateTime eligibleUntil(int maxAge) {
    final limitYear = birthDate.year + maxAge;
    final isLeapDay = birthDate.month == 2 && birthDate.day == 29;
    final leap = (limitYear % 4 == 0 && limitYear % 100 != 0) || limitYear % 400 == 0;
    final limit = isLeapDay && !leap ? DateTime(limitYear, 2, 28) : DateTime(limitYear, birthDate.month, birthDate.day);
    final endOfCourse = DateTime(limit.year, 8, 31);
    return limit.isAfter(endOfCourse) ? DateTime(limit.year + 1, 8, 31) : endOfCourse;
  }

  bool isEligible(int maxAge, {DateTime? on}) {
    final date = on ?? DateTime.now();
    return !DateTime(date.year, date.month, date.day).isAfter(eligibleUntil(maxAge));
  }
}

String? validateCard(String? value) {
  if (value == null || value.isEmpty) return 'Escribe el carné';
  if (!RegExp(r'^\d{11}$').hasMatch(value)) return 'El carné tiene 11 dígitos';
  if (!CardNumber.isValid(value)) return 'Los 6 primeros dígitos no forman una fecha de nacimiento válida';
  return null;
}
