import 'package:intl/intl.dart';

import '../models/models.dart';

/// Sustituye las variables {nombre} de los textos de aviso (docs/02-procesos.md §2.7).
String renderTemplate(String template, Map<String, String> variables) {
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) => variables[match.group(1)] ?? match.group(0)!);
}

/// Fechas como acordamos (docs/09 §8 y §14): día de la semana y año con 2 dígitos, p. ej. "sáb. 31/10/26".
final _weekday = DateFormat('EEE', 'es');
final _date = DateFormat('dd/MM/yy', 'es');
final _time = DateFormat('HH:mm', 'es');

String formatDate(DateTime date) {
  final day = _weekday.format(date);
  return '${day.endsWith('.') ? day : '$day.'} ${_date.format(date)}';
}

String formatTime(DateTime date) => _time.format(date);

String formatDateTime(DateTime date) => '${formatDate(date)} ${formatTime(date)}';

/// Variables de un viaje para los textos de aviso.
Map<String, String> tripVariables(Trip trip, {Map<String, Stop> stops = const {}}) {
  return {
    'itinerario': trip.itineraryName ?? '',
    'tipo': trip.vehicleTypeName ?? 'Transporte',
    'matricula': trip.vehiclePlate ?? '',
    'chofer': trip.driverName ?? '',
    'capacidad': '${trip.totalCapacity}',
    'fecha_salida': formatDate(trip.departsAt),
    'hora_salida': formatTime(trip.departsAt),
    'punto_salida': stops[trip.departureStopId]?.landmark ?? '',
    'fecha_regreso': formatDate(trip.returnsAt),
    'hora_regreso': formatTime(trip.returnsAt),
    'punto_regreso': stops[trip.returnStopId]?.landmark ?? '',
  };
}

final _shortDate = DateFormat('dd/MM/yy', 'es');

/// Fecha corta sin día de la semana, para las tarjetas: "20/01/20" (docs/11 §11.10).
String formatShortDate(DateTime date) => _shortDate.format(date);

/// Igual, desde "AAAA-MM-DD" (fechas sin hora de la API). Vacío si no es válida.
String formatShortDay(String? day) {
  final date = day == null ? null : DateTime.tryParse(day);
  return date == null ? '' : formatShortDate(date);
}
