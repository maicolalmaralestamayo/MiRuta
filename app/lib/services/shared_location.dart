import 'package:flutter/services.dart';

import '../core/api_client.dart';
import 'tracking/worker_tracker.dart';

/// Ubicación compartida desde otras apps (docs/11 §11.51): WhatsApp,
/// Telegram, Google Maps, OsmAnd o cualquier app que comparta una ubicación.
/// MiRuta aparece en el menú «Compartir» (intent-filter ACTION_SEND text/plain
/// y enlaces geo:, ver MainActivity.kt).
class SharedLocation {
  static const _channel = MethodChannel('mitransporte/share');

  /// Lo compartido con la app abierta o al abrirla.
  static void listen(void Function(String text) onShared) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) onShared(call.arguments as String);
    });
    _channel.invokeMethod<String>('initial').then((text) {
      if (text != null && text.isNotEmpty) onShared(text);
    }).catchError((_) {});
  }

  /// Las coordenadas del texto; los enlaces cortos de Google Maps se
  /// resuelven por Internet. null si no hay coordenadas.
  static Future<GeoPoint?> resolve(String text) async {
    final direct = parseLocation(text);
    if (direct != null) return direct;
    final short = shortLink(text);
    if (short == null) return null;
    final target = await ApiClient.resolveRedirect(short);
    return target == null ? null : parseLocation(target);
  }
}

String _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } catch (_) {
    return text.replaceAll('%2C', ',').replaceAll('%2c', ',').replaceAll('%20', ' ');
  }
}

bool _valid(double lat, double lon) => lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0);

GeoPoint? _pair(String? a, String? b) {
  final lat = double.tryParse(a ?? '');
  final lon = double.tryParse(b ?? '');
  if (lat == null || lon == null || !_valid(lat, lon)) return null;
  return GeoPoint(lat, lon);
}

const _number = r'(-?\d{1,3}(?:\.\d+)?)';

/// Coordenadas de un texto compartido: `geo:`, enlaces de Google Maps,
/// OpenStreetMap y OsmAnd, o coordenadas escritas («23.1356, -82.3899»).
GeoPoint? parseLocation(String input) {
  final text = _decode(input.replaceAll('+', ' ')).trim();

  // geo:lat,lon o geo:0,0?q=lat,lon(nombre)
  final geo = RegExp('geo:$_number,$_number(?:[^?\\s]*)(?:\\?q=$_number,\\s*$_number)?').firstMatch(text);
  if (geo != null) {
    final fromQuery = _pair(geo.group(3), geo.group(4));
    final point = fromQuery ?? _pair(geo.group(1), geo.group(2));
    if (point != null) return point;
  }

  // Google Maps: !3dLAT!4dLON (el punto exacto del lugar)
  final pin = RegExp('!3d$_number!4d$_number').firstMatch(text);
  if (pin != null) {
    final p = _pair(pin.group(1), pin.group(2));
    if (p != null) return p;
  }

  // Parámetros: q=, query=, ll=, destination=, daddr=, center=, pin= (OsmAnd)
  final param = RegExp('[?&](?:q|query|ll|sll|destination|daddr|center|pin|loc)=(?:loc:)?$_number\\s*,\\s*$_number').firstMatch(text);
  if (param != null) {
    final p = _pair(param.group(1), param.group(2));
    if (p != null) return p;
  }

  // OpenStreetMap / OsmAnd: mlat=…&mlon=…, lat=…&lon=…
  final mlat = RegExp('[?&]m?lat=$_number').firstMatch(text);
  final mlon = RegExp('[?&]m?lon=$_number').firstMatch(text);
  if (mlat != null && mlon != null) {
    final p = _pair(mlat.group(1), mlon.group(1));
    if (p != null) return p;
  }

  // Google Maps /@lat,lon,17z  y  /maps/search/lat,lon
  final at = RegExp('[@/]$_number,\\s*$_number(?:,|\$|[z/?])').firstMatch(text);
  if (at != null && text.contains('http')) {
    final p = _pair(at.group(1), at.group(2));
    if (p != null) return p;
  }

  // #map=17/lat/lon (OpenStreetMap) o #17/lat/lon (OsmAnd)
  final hash = RegExp('#(?:map=)?\\d{1,2}(?:\\.\\d+)?/$_number/$_number').firstMatch(text);
  if (hash != null) {
    final p = _pair(hash.group(1), hash.group(2));
    if (p != null) return p;
  }

  // Coordenadas escritas: «23.1356, -82.3899» o «23.1356 -82.3899» (con decimales).
  final plain = RegExp(r'(?<![\d.])(-?\d{1,2}\.\d{3,})\s*[,;\s]\s*(-?\d{1,3}\.\d{3,})(?![\d.])').firstMatch(text);
  if (plain != null) return _pair(plain.group(1), plain.group(2));
  return null;
}

/// Enlace corto que hay que resolver por Internet (Google Maps, OsmAnd…).
String? shortLink(String text) {
  final match = RegExp(r'https?://(?:maps\.app\.goo\.gl|goo\.gl/maps|g\.co/kgs|maps\.google\.[a-z.]+/\?cid|osmand\.net/go|osm\.org/go)[^\s]*').firstMatch(text);
  return match?.group(0);
}
