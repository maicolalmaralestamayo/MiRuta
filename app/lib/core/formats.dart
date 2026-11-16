import 'package:intl/intl.dart';

/// Formatos de fechas y horas de toda la app (docs/11 §11.33 y §11.65):
/// fechas «sáb. 07-11-26» y horas de 12 h «05:30 p. m.».
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

String formatTime(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return time12(local.hour, local.minute);
}

/// «05:00 p. m.», «12:30 a. m.» (docs/11 §11.65: horas de 12 h con a. m. / p. m.).
String time12(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '${h.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// «17:30» (como lo guarda el servidor) → «05:30 p. m.»; si no se entiende, tal cual.
String hhmm12(String hhmm) {
  final parts = hhmm.split(':');
  final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return h == null || m == null ? hhmm : time12(h, m);
}

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
