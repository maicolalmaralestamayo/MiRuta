/// Nombre de usuario para iniciar sesión. Mismas reglas que la API
/// (api/app/Support/Username.php): de 3 a 30 caracteres, empieza por letra,
/// solo letras sin tilde, números, punto y guion bajo; en minúsculas.
class Username {
  static final pattern = RegExp(r'^[a-z][a-z0-9._]{2,29}$');
  static final _card = RegExp(r'^\d{11}$');

  static String normalize(String value) => value.trim().toLowerCase();

  static bool isValid(String value) => pattern.hasMatch(normalize(value));

  /// Lo escrito en "Usuario" es un carné (se admite como alternativa).
  static bool isCardNumber(String value) => _card.hasMatch(value.trim());

  /// Propuesta: primer nombre y primer apellido sin tildes ("María José
  /// Pérez Díaz" → "maria.perez"). Si está ocupado, la API lo dirá.
  static String suggest(String firstName, String lastName) {
    final base = [firstName, lastName].map(_firstWord).map(_slug).where((part) => part.isNotEmpty).join('.');
    var result = base.isEmpty || !RegExp('[a-z]').hasMatch(base[0]) ? 'usuario$base' : base;
    if (result.length > 27) result = result.substring(0, 27);
    return result.length < 3 ? result.padRight(3, '0') : result;
  }

  static String _firstWord(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    return words.isEmpty ? '' : words.first;
  }

  static const _accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n', 'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u', 'ç': 'c'};

  static String _slug(String text) =>
      text.toLowerCase().split('').map((char) => _accents[char] ?? char).join().replaceAll(RegExp('[^a-z0-9]'), '');
}

String? validateUsername(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Escribe un usuario';
  if (text.length < 3 || text.length > 30) return 'De 3 a 30 caracteres';
  if (!RegExp('^[a-zA-Z]').hasMatch(text)) return 'Tiene que empezar por una letra';
  if (!Username.isValid(text)) return 'Solo letras sin tilde, números, punto y guion bajo';
  return null;
}
