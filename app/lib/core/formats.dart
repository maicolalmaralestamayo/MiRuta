import 'package:intl/intl.dart';

import 'server_clock.dart';

/// Formatos de fechas y horas de toda la app (docs/11 §11.63 y §11.67):
/// «Jue. 19/11/26 10:30», horas de 24 h, en la zona del servidor
/// (ServerClock), como en las notificaciones.
const _weekdays = ['Lun.', 'Mar.', 'Mié.', 'Jue.', 'Vie.', 'Sáb.', 'Dom.'];

String _two(int n) => n.toString().padLeft(2, '0');

/// La fecha y hora que se muestran. Un día sin hora (medianoche local, como
/// los que da [parseDay]) se muestra tal cual; un instante, en la zona del
/// servidor.
DateTime _shown(DateTime date) {
  final local = date.isUtc ? date.toLocal() : date;
  final calendarDay = !date.isUtc && local.hour == 0 && local.minute == 0 && local.second == 0 && local.millisecond == 0;
  return calendarDay ? local : ServerClock.wall(date);
}

/// «Jue. 19/11/26».
String formatDate(DateTime? date) {
  if (date == null) return '';
  final d = _shown(date);
  return '${weekday(d)} ${_two(d.day)}/${_two(d.month)}/${_two(d.year % 100)}';
}

/// Día de la semana abreviado con mayúscula y punto: «Jue.».
String weekday(DateTime date) => _weekdays[date.weekday - 1];

/// «10:30» (24 h).
String formatTime(DateTime? date) {
  if (date == null) return '';
  final d = ServerClock.wall(date);
  return time24(d.hour, d.minute);
}

/// «07:05», «17:30».
String time24(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// «17:30» (como lo guarda el servidor) → «17:30»; si no se entiende, tal cual.
String hhmm24(String hhmm) {
  final parts = hhmm.split(':');
  final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return h == null || m == null ? hhmm : time24(h, m);
}

/// «Jue. 19/11/26 10:30».
String formatDateTime(DateTime? date) {
  if (date == null) return '';
  final d = ServerClock.wall(date);
  return '${weekday(d)} ${_two(d.day)}/${_two(d.month)}/${_two(d.year % 100)} ${time24(d.hour, d.minute)}';
}

/// Un día (AAAA-MM-DD) y una hora «HH:MM» como se planificaron: «Jue. 19/11/26 10:30».
String formatDayTime(DateTime day, String hhmm) => '${formatDate(DateTime(day.year, day.month, day.day))} ${hhmm24(hhmm)}';

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
