import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/server_url.dart';

void main() {
  test('sin protocolo se prueba primero HTTPS y después HTTP', () {
    expect(ServerUrl.candidates('transporte.ejemplo.org'), ['https://transporte.ejemplo.org/api/v1', 'http://transporte.ejemplo.org/api/v1']);
    expect(ServerUrl.candidates('192.168.1.10:8000/'), ['https://192.168.1.10:8000/api/v1', 'http://192.168.1.10:8000/api/v1']);
  });

  test('con protocolo se respeta el que escribió', () {
    expect(ServerUrl.candidates(' https://transporte.ejemplo.org/ '), ['https://transporte.ejemplo.org/api/v1']);
    expect(ServerUrl.candidates('http://ejemplo.org:8080/api/v1'), ['http://ejemplo.org:8080/api/v1']);
    expect(ServerUrl.candidates('https://ejemplo.org/mitransporte/api/v1/'), ['https://ejemplo.org/mitransporte/api/v1']);
  });

  test('rechaza direcciones no válidas', () {
    expect(ServerUrl.isValid(''), isFalse);
    expect(ServerUrl.isValid('hola mundo'), isFalse);
    expect(ServerUrl.isValid('servidor'), isFalse);
    expect(ServerUrl.isValid('ftp://ejemplo.org'), isFalse);
  });

  test('forma corta para mostrar', () {
    expect(ServerUrl.short('https://transporte.ejemplo.org/api/v1'), 'transporte.ejemplo.org');
    expect(ServerUrl.short('http://192.168.1.10:8000/api/v1'), 'http://192.168.1.10:8000');
    expect(ServerUrl.isPlain('http://192.168.1.10:8000/api/v1'), isTrue);
  });
}
