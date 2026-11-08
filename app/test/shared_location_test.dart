import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/services/shared_location.dart';

void main() {
  void expectPoint(String text, double lat, double lon) {
    final p = parseLocation(text);
    expect(p, isNotNull, reason: text);
    expect(p!.latitude, closeTo(lat, 1e-6), reason: text);
    expect(p.longitude, closeTo(lon, 1e-6), reason: text);
  }

  test('enlaces geo:', () {
    expectPoint('geo:23.1356,-82.3899', 23.1356, -82.3899);
    expectPoint('geo:0,0?q=23.1356,-82.3899(Coppelia)', 23.1356, -82.3899);
    expectPoint('geo:23.1356,-82.3899?z=17', 23.1356, -82.3899);
  });

  test('Google Maps (WhatsApp y Telegram comparten así)', () {
    expectPoint('https://maps.google.com/?q=23.1356,-82.3899', 23.1356, -82.3899);
    expectPoint('Mi ubicación: https://www.google.com/maps/search/?api=1&query=23.1356%2C-82.3899', 23.1356, -82.3899);
    expectPoint('https://www.google.com/maps/place/Coppelia/@23.1400,-82.3800,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d23.1356!4d-82.3899', 23.1356, -82.3899);
    expectPoint('https://www.google.com/maps/@23.1356,-82.3899,15z', 23.1356, -82.3899);
    expectPoint('https://maps.google.com/maps?ll=23.1356,-82.3899&z=16', 23.1356, -82.3899);
  });

  test('OpenStreetMap y OsmAnd', () {
    expectPoint('https://www.openstreetmap.org/?mlat=23.1356&mlon=-82.3899#map=17/23.1356/-82.3899', 23.1356, -82.3899);
    expectPoint('https://www.openstreetmap.org/#map=17/23.1356/-82.3899', 23.1356, -82.3899);
    expectPoint('https://osmand.net/map?pin=23.1356,-82.3899#17/23.1356/-82.3899', 23.1356, -82.3899);
    expectPoint('https://osmand.net/go?lat=23.1356&lon=-82.3899&z=17', 23.1356, -82.3899);
  });

  test('coordenadas escritas', () {
    expectPoint('23.1356, -82.3899', 23.1356, -82.3899);
    expectPoint('Parada nueva: 23.135612 -82.389901 frente al cine', 23.135612, -82.389901);
  });

  test('sin coordenadas y enlaces cortos', () {
    expect(parseLocation('Hola, nos vemos en Coppelia'), isNull);
    expect(parseLocation('https://maps.app.goo.gl/AbCdEf123'), isNull);
    expect(shortLink('Mira https://maps.app.goo.gl/AbCdEf123 ahora'), 'https://maps.app.goo.gl/AbCdEf123');
    expect(shortLink('https://goo.gl/maps/xyz'), 'https://goo.gl/maps/xyz');
    expect(shortLink('texto sin enlaces'), isNull);
  });
}
