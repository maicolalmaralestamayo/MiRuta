import 'json_api.dart';

/// Error devuelto por la API (o de red), con los errores JSON:API.
class ApiException implements Exception {
  final int? statusCode;
  final List<JsonApiError> errors;

  ApiException(this.statusCode, this.errors);

  factory ApiException.network() => ApiException(null, [
        JsonApiError(status: '', code: 'NETWORK_ERROR', title: 'Sin conexión', detail: 'No se pudo conectar con el servidor. Revisa tu conexión.'),
      ]);

  String get code => errors.isEmpty ? 'ERROR' : errors.first.code;

  bool hasCode(String code) => errors.any((error) => error.code == code);

  bool get isNetwork => code == 'NETWORK_ERROR';

  /// Mensaje en español para mostrar al usuario.
  String get message => errors.isEmpty ? 'Ocurrió un error inesperado.' : errors.map((error) => error.message).toSet().join('\n');

  /// Mensaje del error de un campo (por su pointer, p. ej. "/data/attributes/cardNumber").
  String? fieldError(String pointerSuffix) {
    for (final error in errors) {
      if (error.pointer != null && error.pointer!.endsWith(pointerSuffix)) return error.message;
    }
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
