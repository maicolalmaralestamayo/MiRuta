import 'package:flutter_test/flutter_test.dart';
import 'package:mitransporte/core/username.dart';

void main() {
  test('reglas del usuario (las mismas que la API)', () {
    for (final ok in ['maria', 'Maria.Perez', 'mj_perez2', 'abc1', 'ab', 'maicol.alberto.almarales.tamayo.2']) {
      expect(validateUsername(ok), isNull, reason: ok);
    }
    final bad = {
      'a': 'corto',
      'a' * 51: 'largo',
      '1maria': 'empieza por número',
      'maria.': 'termina en signo',
      'ma..ria': 'dos signos seguidos',
      'a1234567': 'menos de 2 letras',
      'maaaaria': 'repite más de 3 veces',
      'maría': 'tilde',
      'el.admin': 'palabra reservada',
      'soport3': 'reservada con número camuflado',
    };
    bad.forEach((value, reason) => expect(validateUsername(value), isNotNull, reason: reason));
  });

  test('se guarda en minúsculas', () {
    expect(Username.normalize('  Maria.Perez '), 'maria.perez');
  });
}
