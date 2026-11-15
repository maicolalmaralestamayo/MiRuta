/// Textos de las notificaciones (docs/11 §11.63). Código puro, sin plugins:
/// se prueba en test/. Cada notificación es un título, unas líneas y, si
/// toca, una línea destacada al final (en naranja donde Android lo permite).
library;

/// Contenido de una notificación.
class NoticeContent {
  final String title;
  final List<String> lines;

  /// Línea destacada (naranja), la última.
  final String? highlight;

  const NoticeContent(this.title, [this.lines = const [], this.highlight]);

  /// Todas las líneas debajo del título, con la destacada al final.
  List<String> get allLines => [...lines, ?highlight];

  /// Texto plano (líneas separadas por saltos de línea).
  String get text => allLines.join('\n');

  @override
  String toString() => [title, ...allLines].join('\n');
}

const _weekdays = ['Lun.', 'Mar.', 'Mié.', 'Jue.', 'Vie.', 'Sáb.', 'Dom.'];

String _two(int n) => n.toString().padLeft(2, '0');

/// «Lun. 16/11/26 07:00».
String noticeDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${_two(d.day)}/${_two(d.month)}/${_two(d.year % 100)} ${_two(d.hour)}:${_two(d.minute)}';

/// «Ruta 1 • ida».
String itineraryLine(String? itinerary, String direction) => '${itinerary == null || itinerary.isEmpty ? 'Viaje' : itinerary} • ${direction == 'ida' ? 'ida' : 'regreso'}';

/// Campos que pueden cambiar en un viaje, en el orden en que se nombran
/// (claves de `data.changes` del servidor).
const tripChangeNames = {
  'fecha': 'fecha',
  'hora': 'hora',
  'tipo_vehiculo': 'tipo de vehículo',
  'observacion': 'observación',
  'parada_salida': 'parada de salida',
};

/// «Cambió la hora», «Cambió la fecha y hora», «Cambió la fecha, hora y tipo
/// de vehículo», «Cambió el tipo de vehículo». Null si no cambió nada conocido.
String? changesLine(Iterable<String> changes) {
  final names = [
    for (final e in tripChangeNames.entries)
      if (changes.contains(e.key)) e.value,
  ];
  if (names.isEmpty) return null;
  final article = names.first == 'tipo de vehículo' ? 'el' : 'la';
  final joined = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  return 'Cambió $article $joined';
}

/// Estado de la notificación del viaje.
const tripNoticeStatus = {
  'planificado': 'planificado',
  'cambiado': 'cambiado',
  'en_ejecucion': 'en ejecución',
  'cancelado': 'cancelado',
  'eliminado': 'eliminado',
};

/// «Viaje planificado / cambiado / en ejecución / cancelado / eliminado».
/// [status] es el de la notificación ('cambiado' tras una modificación).
NoticeContent tripNotice({
  required String status,
  String? itineraryName,
  String direction = 'ida',
  DateTime? departsAt,
  String? departureStop,
  String? vehicleType,
  Iterable<String> changes = const [],
}) {
  final third = [?departureStop, ?vehicleType].where((s) => s.isNotEmpty).join(' • ');
  return NoticeContent(
    'Viaje ${tripNoticeStatus[status] ?? status}',
    [
      itineraryLine(itineraryName, direction),
      if (departsAt != null) noticeDate(departsAt),
      if (third.isNotEmpty) third,
    ],
    status == 'cambiado' ? changesLine(changes) : null,
  );
}

/// Lo que ve el teléfono del vehículo (de la línea del recorrido).
class VehicleView {
  final String vehicleType;
  final String? itineraryName;
  final bool outbound;

  /// detenido, en_movimiento o null (sin datos).
  final String? state;

  /// Sensores activos.
  final int sensors;

  /// Nombres de las paradas en el orden del recorrido.
  final List<String> stops;

  /// Próxima parada (posición en [stops]; 0 = salida).
  final int nextStopIndex;

  /// Detenido en el radio de la próxima parada.
  final bool atStop;

  /// El vehículo ya se movió alguna vez en este viaje (ya no está en la primera parada).
  final bool movedOnce;

  const VehicleView({
    required this.vehicleType,
    this.itineraryName,
    this.outbound = true,
    this.state,
    this.sensors = 0,
    this.stops = const [],
    this.nextStopIndex = 0,
    this.atStop = false,
    this.movedOnce = false,
  });

  bool get noData => state == null || sensors == 0;
}

/// Líneas de paradas y destacada del vehículo (sin la del itinerario):
/// «Anterior / Próxima», «Primera parada», «Última parada», «Recogiendo en …»
/// o «Dejando en …» (docs/11 §11.63).
(List<String>, String?) vehicleStopLines(VehicleView v) {
  final stops = v.stops;
  if (stops.isEmpty) return (const [], null);
  final n = v.nextStopIndex.clamp(0, stops.length);
  String at(int i) => stops[i];
  // En la primera parada: aún no se movió desde la salida.
  if (n <= 1 && !v.movedOnce) {
    return (['Próxima: ${at(stops.length > 1 ? 1 : 0)}'], 'Primera parada');
  }
  // En la última: la pasó (ida) o está detenido en ella.
  if (n >= stops.length || (n == stops.length - 1 && v.atStop && v.state == 'detenido')) {
    return ([if (stops.length > 1) 'Anterior: ${at(stops.length - 2)}'], 'Última parada');
  }
  // Detenido en una parada intermedia: recogiendo (regreso) o dejando (ida).
  if (v.atStop && v.state == 'detenido') {
    return ([if (n + 1 < stops.length) 'Próxima: ${at(n + 1)}'], '${v.outbound ? 'Dejando' : 'Recogiendo'} en ${at(n)}');
  }
  return ([if (n > 0) 'Anterior: ${at(n - 1)}', 'Próxima: ${at(n)}'], null);
}

/// Notificación del vehículo. Sin datos (ningún sensor) se queda con las
/// últimas líneas conocidas ([lastLines]) y destaca «Sin datos».
NoticeContent vehicleNotice(VehicleView v, {List<String> lastLines = const []}) {
  final header = itineraryLine(v.itineraryName, v.outbound ? 'ida' : 'regreso');
  if (v.noData) return NoticeContent(v.vehicleType, [header, ...lastLines], 'Sin datos');
  final (lines, highlight) = vehicleStopLines(v);
  return NoticeContent('${v.vehicleType} • ${v.state == 'detenido' ? 'detenido' : 'en movimiento'}', [header, ...lines], highlight);
}

/// «Mi estado» (la notificación fija del servicio de ubicación). Sin GPS solo
/// «Active la ubicación (GPS)»; sin «Permitir todo el tiempo», solo «Permita
/// la ubicación todo el tiempo» (primero el GPS).
NoticeContent myStateNotice({
  required String stateName,
  String? state,
  String? itineraryName,
  bool outbound = true,
  String? myStop,
  bool gpsOn = true,
  bool alwaysPermission = true,
  bool ended = false,
}) {
  if (!gpsOn) return const NoticeContent(myStateGpsOff);
  if (!alwaysPermission) return const NoticeContent(myStatePermission);
  final highlight = ended
      ? 'Ya puede quitar la ubicación'
      : switch (state) {
          'dormido' => 'Llegó tarde a la parada',
          'botado' => 'El vehículo pasó sin recogerle',
          _ => null,
        };
  return NoticeContent(stateName, [
    itineraryLine(itineraryName, outbound ? 'ida' : 'regreso'),
    if (myStop != null && myStop.isNotEmpty) 'Mi parada: $myStop',
  ], highlight);
}

const myStateGpsOff = 'Active la ubicación (GPS)';
const myStatePermission = 'Permita la ubicación todo el tiempo';

/// «3 solicitudes pendientes» con «Entidad: 1 • Itinerario: 2» (solo los
/// tipos con alguna). Null si no hay ninguna.
NoticeContent? pendingApplicationsNotice({int entity = 0, int itinerary = 0, int accessRecovery = 0}) {
  final total = entity + itinerary + accessRecovery;
  if (total <= 0) return null;
  final parts = [
    if (entity > 0) 'Entidad: $entity',
    if (itinerary > 0) 'Itinerario: $itinerary',
    if (accessRecovery > 0) 'Olvidé algo: $accessRecovery',
  ];
  return NoticeContent(total == 1 ? '1 solicitud pendiente' : '$total solicitudes pendientes', [parts.join(' • ')]);
}

/// «Solicitud aprobada / rechazada» de una solicitud propia.
NoticeContent resolvedApplicationNotice({
  required bool approved,
  required String type,
  String? entity,
  String? itinerary,
  String? stop,
  DateTime? resolvedAt,
  String? reason,
  String? note,
}) {
  final motive = [?reason, ?note].where((s) => s.trim().isNotEmpty).join('. ');
  return NoticeContent(approved ? 'Solicitud aprobada' : 'Solicitud rechazada', [
    if (type == 'entidad') 'Entidad: ${entity ?? ''}' else 'Itinerario: ${itinerary ?? ''}${entity == null || entity.isEmpty ? '' : ' • $entity'}',
    if (type != 'entidad' && stop != null && stop.isNotEmpty) 'Parada: $stop',
    if (resolvedAt != null) noticeDate(resolvedAt),
  ], approved || motive.isEmpty ? null : 'Motivo: $motive');
}

/// «Respuesta del desarrollador»: el último mensaje, su hora y, con más de
/// uno sin leer, «N mensajes sin leer».
NoticeContent developerReplyNotice({required String text, DateTime? sentAt, int unread = 1}) =>
    NoticeContent('Respuesta del desarrollador', [text, if (sentAt != null) noticeDate(sentAt)], unread > 1 ? '$unread mensajes sin leer' : null);

/// «Actualización disponible / obligatoria».
NoticeContent updateNotice({required String versionName, bool mandatory = false, String? size}) => NoticeContent(
      mandatory ? 'Actualización obligatoria' : 'Actualización disponible',
      ['Versión $versionName', if (size != null && size.isNotEmpty) 'Tamaño: $size'],
      mandatory ? 'Instálela para seguir usando MiRuta' : null,
    );

/// Escapa el texto para el formato HTML de la notificación.
String htmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Color de la línea destacada (naranja).
const highlightColor = '#E65100';

/// Cuerpo en HTML: las líneas separadas por <br> y la destacada en naranja.
String noticeHtml(NoticeContent c) => [
      for (final l in c.lines) htmlEscape(l),
      if (c.highlight != null) '<font color="$highlightColor"><b>${htmlEscape(c.highlight!)}</b></font>',
    ].join('<br>');
