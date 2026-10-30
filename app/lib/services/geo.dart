import 'dart:math';

/// Distancia en metros entre dos puntos (haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const radius = 6371000.0;
  double rad(double degrees) => degrees * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * radius * asin(min(1.0, sqrt(a)));
}
