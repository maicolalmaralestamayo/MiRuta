/// Valores de los ajustes con unidades (docs/11 §11.40 y §11.43): tiempos
/// `seg min hor dia sem mes ano` (mes = 30 días, año = 365), distancias
/// `m km` y velocidades distancia/tiempo (`10km/hor`), combinables
/// (`12hor30min`, `1km200m`).
library;

const _timeUnits = {'seg': 1, 'min': 60, 'hor': 3600, 'dia': 86400, 'sem': 604800, 'mes': 2592000, 'ano': 31536000};
const _distanceUnits = {'km': 1000, 'm': 1};

final _part = RegExp(r'(\d+(?:[.,]\d+)?)\s*([a-z]+)');

double? _combined(String text, Map<String, int> units) {
  final clean = text.trim().toLowerCase().replaceAll('ñ', 'n');
  if (clean.isEmpty) return null;
  if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(clean)) return double.parse(clean.replaceAll(',', '.'));
  var total = 0.0;
  var consumed = 0;
  for (final match in _part.allMatches(clean)) {
    final factor = units[match.group(2)];
    if (factor == null) return null;
    total += double.parse(match.group(1)!.replaceAll(',', '.')) * factor;
    consumed += match.group(0)!.replaceAll(' ', '').length;
  }
  if (consumed != clean.replaceAll(' ', '').length) return null;
  return total;
}

/// `12hor30min` → 12 h 30 min. Un número solo son segundos.
Duration? parseDuration(String? text) {
  final seconds = _combined(text ?? '', _timeUnits);
  return seconds == null ? null : Duration(milliseconds: (seconds * 1000).round());
}

/// `1km200m` → 1200 (metros). Un número solo son metros.
double? parseDistance(String? text) => _combined(text ?? '', _distanceUnits);

/// `10km/hor` → metros por segundo.
double? parseSpeed(String? text) {
  final parts = (text ?? '').split('/');
  if (parts.length != 2) return null;
  final distance = parseDistance(parts[0]);
  final time = _combined(RegExp(r'^\d').hasMatch(parts[1].trim()) ? parts[1] : '1${parts[1].trim()}', _timeUnits);
  if (distance == null || time == null || time == 0) return null;
  return distance / time;
}
