import 'json_api.dart';

/// Requisitos de la contraseña (ajustes de la app). La app los muestra y los
/// comprueba mientras se escribe; quien decide es la API.
class PasswordPolicy {
  final int minLength;
  final int requiredClasses;
  final bool forbidPersonalData;
  final int historyCount;
  final int expiryDays;

  const PasswordPolicy({this.minLength = 8, this.requiredClasses = 3, this.forbidPersonalData = true, this.historyCount = 5, this.expiryDays = 365});

  factory PasswordPolicy.from(Resource r) => PasswordPolicy(
        minLength: r.integer('minLength') ?? 8,
        requiredClasses: r.integer('requiredClasses') ?? 3,
        forbidPersonalData: r.attributes['forbidPersonalData'] != false,
        historyCount: r.integer('historyCount') ?? 5,
        expiryDays: r.integer('expiryDays') ?? 365,
      );

  String get description =>
      'Al menos $minLength caracteres y $requiredClasses de estos tipos: mayúsculas, minúsculas, números y símbolos.'
      '${forbidPersonalData ? ' Sin tu usuario ni tus nombres.' : ''}'
      '${historyCount > 0 ? ' Distinta de las $historyCount anteriores.' : ''}';

  static int classCount(String password) =>
      [RegExp(r'\p{Lu}', unicode: true), RegExp(r'\p{Ll}', unicode: true), RegExp(r'\d'), RegExp(r'[^\p{L}\d]', unicode: true)]
          .where((pattern) => pattern.hasMatch(password))
          .length;

  /// Lo que falta, o null si cumple lo que se puede comprobar en el teléfono.
  String? validate(String? password, {List<String> personal = const []}) {
    final text = password ?? '';
    if (text.length < minLength) return 'Al menos $minLength caracteres';
    if (classCount(text) < requiredClasses) return 'Combina $requiredClasses tipos: mayúsculas, minúsculas, números y símbolos';
    if (forbidPersonalData) {
      final lower = text.toLowerCase();
      for (final value in personal) {
        final part = value.trim().toLowerCase();
        if (part.length >= 3 && lower.contains(part)) return 'No puede contener tu usuario ni tus nombres';
      }
    }
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
