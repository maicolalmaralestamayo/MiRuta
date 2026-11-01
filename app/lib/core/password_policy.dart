import 'json_api.dart';

/// Requisitos de la contraseña (ajustes de la app). La app los comprueba
/// mientras se escribe; quien decide es la API (además, que sea distinta de
/// las anteriores). Ya no se comprueban contraseñas comunes ni que contenga
/// el usuario o los nombres (docs/09 §32).
class PasswordPolicy {
  final int minLength;
  final int requiredClasses;
  final int historyCount;
  final int expiryDays;

  const PasswordPolicy({this.minLength = 8, this.requiredClasses = 3, this.historyCount = 5, this.expiryDays = 365});

  factory PasswordPolicy.from(Resource r) => PasswordPolicy(
        minLength: r.integer('minLength') ?? 8,
        requiredClasses: r.integer('requiredClasses') ?? 3,
        historyCount: r.integer('historyCount') ?? 5,
        expiryDays: r.integer('expiryDays') ?? 365,
      );

  static int classCount(String password) =>
      [RegExp(r'\p{Lu}', unicode: true), RegExp(r'\p{Ll}', unicode: true), RegExp(r'\d'), RegExp(r'[^\p{L}\d]', unicode: true)]
          .where((pattern) => pattern.hasMatch(password))
          .length;

  /// Lo que falta, o null si cumple lo que se puede comprobar en el teléfono.
  String? validate(String? password) {
    final text = password ?? '';
    if (text.isEmpty) return 'Escriba la contraseña';
    if (text.length < minLength) return 'Escriba al menos $minLength caracteres';
    if (classCount(text) < requiredClasses) return 'Combine al menos $requiredClasses tipos: mayúsculas, minúsculas, números y símbolos';
    return null;
  }

  static PasswordPolicy? _cached;

  /// Requisitos actuales (se piden al servidor una vez por sesión de la app).
  static Future<PasswordPolicy> load(Future<JsonApiDocument> Function() fetch) async {
    if (_cached != null) return _cached!;
    try {
      _cached = PasswordPolicy.from((await fetch()).resource);
    } catch (_) {
      return const PasswordPolicy();
    }
    return _cached!;
  }
}
