import 'package:intl/intl.dart';

/// Formatos de fechas y horas de toda la app (docs/11 §11.33): fechas
/// «sáb. 07-11-26» y horas de 24 h «17:30».
String formatDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return '${weekday(local)} ${DateFormat('dd-MM-yy').format(local)}';
}

/// Día de la semana abreviado con punto: «sáb.».
String weekday(DateTime date) {
  const names = ['lun.', 'mar.', 'mié.', 'jue.', 'vie.', 'sáb.', 'dom.'];
  return names[date.weekday - 1];
}

String formatTime(DateTime? date) => date == null ? '' : DateFormat('HH:mm').format(date.toLocal());

String formatDateTime(DateTime? date) => date == null ? '' : '${formatDate(date)} ${formatTime(date)}';

/// Día para la API: AAAA-MM-DD.
String apiDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// Día de la API (AAAA-MM-DD) como fecha local.
DateTime? parseDay(String? text) {
  if (text == null || text.isEmpty) return null;
  final parts = text.split('-');
  if (parts.length != 3) return DateTime.tryParse(text);
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2].substring(0, 2)));
}

/// «1 asiento», «3 asientos».
String plural(int count, String one, String many) => '$count ${count == 1 ? one : many}';

String sizeLabel(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB' : '${(bytes / 1024).toStringAsFixed(0)} KB';
