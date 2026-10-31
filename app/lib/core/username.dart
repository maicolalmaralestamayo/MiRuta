/// Nombre de usuario (docs/08-version-2.md §8.3). Mismas reglas de formato
/// que la API (api/app/Support/Username.php); las palabras no permitidas y
/// si ya existe solo los comprueba el servidor.
class Username {
  static const minLength = 4;
  static const maxLength = 20;

  /// Nadie puede hacerse pasar por la app o por su equipo.
  static const reserved = [
    'admin', 'administrador', 'administrator', 'soporte', 'support', 'sistema', 'system',
    'mitransporte', 'root', 'moderador', 'moderator', 'desarrollador', 'developer', 'oficial',
  ];

  static const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '9': 'g'};

  static String normalize(String value) => value.trim().toLowerCase();

  static bool isValid(String value) => validateUsername(value) == null;

  static bool containsReservedWord(String value) {
    final plain = normalize(value).split('').map((char) => _leet[char] ?? char).join().replaceAll(RegExp('[^a-z]'), '');
    return reserved.any(plain.contains);
  }
}

String? validateUsername(String? value) {
  final text = Username.normalize(value ?? '');
  if (text.isEmpty) return 'Escribe un usuario';
  if (text.length < Username.minLength || text.length > Username.maxLength) {
    return 'De ${Username.minLength} a ${Username.maxLength} caracteres';
  }
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(text)) return 'Solo letras sin tilde, números, punto y guion bajo';
  if (!RegExp('^[a-z]').hasMatch(text)) return 'Tiene que empezar por una letra';
  if (RegExp(r'[._]$').hasMatch(text)) return 'No puede terminar en punto ni en guion bajo';
  if (RegExp(r'[._]{2}').hasMatch(text)) return 'No puede tener dos signos seguidos';
  if (RegExp('[a-z]').allMatches(text).length < 3) return 'Tiene que tener al menos 3 letras';
  if (RegExp(r'(.)\1{3}').hasMatch(text)) return 'No repitas un carácter más de 3 veces seguidas';
  if (Username.containsReservedWord(text)) return 'No puede contener palabras reservadas de la app';
  return null;
}
