import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/server_url.dart';

void main() {
  test('completa la dirección del servidor', () {
    expect(ServerUrl.normalize('transporte.ejemplo.org'), 'https://transporte.ejemplo.org/api/v1');
    expect(ServerUrl.normalize(' https://transporte.ejemplo.org/ '), 'https://transporte.ejemplo.org/api/v1');
    expect(ServerUrl.normalize('https://ejemplo.org/mitransporte/api/v1/'), 'https://ejemplo.org/mitransporte/api/v1');
    expect(ServerUrl.normalize('192.168.1.10:8443'), 'https://192.168.1.10:8443/api/v1');
    expect(ServerUrl.normalize('http://ejemplo.org:8080/api/v1'), 'http://ejemplo.org:8080/api/v1');
  });

  test('rechaza direcciones no válidas', () {
    expect(ServerUrl.normalize(''), isNull);
    expect(ServerUrl.normalize('hola mundo'), isNull);
    expect(ServerUrl.normalize('servidor'), isNull);
    expect(ServerUrl.normalize('ftp://ejemplo.org'), isNull);
  });

  test('forma corta para mostrar', () {
    expect(ServerUrl.short('https://transporte.ejemplo.org/api/v1'), 'transporte.ejemplo.org');
    expect(ServerUrl.short('http://192.168.1.10:8000/api/v1'), 'http://192.168.1.10:8000');
  });
}
