import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/username.dart';

void main() {
  test('propuesta a partir del nombre, sin tildes', () {
    expect(Username.suggest('María José', 'Pérez Díaz'), 'maria.perez');
    expect(Username.suggest('Núñez', 'Ibáñez'), 'nunez.ibanez');
    expect(Username.suggest('2X', ''), 'usuario2x');
    expect(Username.isValid(Username.suggest('a' * 40, 'b' * 40)), isTrue);
  });

  test('mismas reglas que la API', () {
    for (final ok in ['maria', 'Maria.Perez', 'm_j.perez2', 'abc']) {
      expect(validateUsername(ok), isNull, reason: ok);
    }
    for (final bad in ['', 'ab', '1maria', '92071648863', 'maría', 'maria perez', 'a' * 31]) {
      expect(validateUsername(bad), isNotNull, reason: bad);
    }
  });

  test('el carné se reconoce como alternativa', () {
    expect(Username.isCardNumber(' 92071648863 '), isTrue);
    expect(Username.isCardNumber('maria'), isFalse);
    expect(Username.normalize('  Maria.Perez '), 'maria.perez');
  });
}
