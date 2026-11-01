import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/server_url.dart';

void main() {
  test('construye la URL con el protocolo elegido', () {
    expect(ServerUrl.build('https', 'transporte.ejemplo.org'), 'https://transporte.ejemplo.org/api/v1');
    expect(ServerUrl.build('http', '192.168.1.10:8000/'), 'http://192.168.1.10:8000/api/v1');
    expect(ServerUrl.build('https', ' ejemplo.org/mitransporte/api/v1/ '), 'https://ejemplo.org/mitransporte/api/v1');
  });

  test('si la dirección trae protocolo, manda el que trae', () {
    expect(ServerUrl.build('https', 'http://ejemplo.org:8080/api/v1'), 'http://ejemplo.org:8080/api/v1');
    expect(ServerUrl.fromInput('transporte.ejemplo.org'), 'https://transporte.ejemplo.org/api/v1');
  });

  test('separa una URL pegada en protocolo y dirección', () {
    final pasted = ServerUrl.split(' HTTP://ejemplo.org:8080/api/v1/ ');
    expect(pasted.protocol, 'http');
    expect(pasted.address, 'ejemplo.org:8080');
    final saved = ServerUrl.split('https://ejemplo.org/mitransporte/api/v1');
    expect(saved.protocol, 'https');
    expect(saved.address, 'ejemplo.org/mitransporte');
    final plain = ServerUrl.split('transporte.ejemplo.org');
    expect(plain.protocol, isNull);
    expect(plain.address, 'transporte.ejemplo.org');
  });

  test('rechaza direcciones no válidas', () {
    expect(ServerUrl.isValid(''), isFalse);
    expect(ServerUrl.isValid('hola mundo'), isFalse);
    expect(ServerUrl.isValid('servidor'), isFalse);
    expect(ServerUrl.isValid('ftp://ejemplo.org'), isFalse);
    expect(ServerUrl.build('ftp', 'ejemplo.org'), isNull);
  });

  test('forma corta para mostrar', () {
    expect(ServerUrl.short('https://transporte.ejemplo.org/api/v1'), 'transporte.ejemplo.org');
    expect(ServerUrl.short('http://192.168.1.10:8000/api/v1'), 'http://192.168.1.10:8000');
    expect(ServerUrl.isPlain('http://192.168.1.10:8000/api/v1'), isTrue);
  });
}
