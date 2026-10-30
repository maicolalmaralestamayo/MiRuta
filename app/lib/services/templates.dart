import 'package:intl/intl.dart';

import '../models/models.dart';

/// Sustituye las variables {nombre} de los textos de aviso (docs/02-procesos.md §2.7).
String renderTemplate(String template, Map<String, String> variables) {
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) => variables[match.group(1)] ?? match.group(0)!);
}

final _date = DateFormat('dd/MM/yyyy', 'es');
final _time = DateFormat('HH:mm', 'es');

String formatDate(DateTime date) => _date.format(date);

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
