/// Dirección del servidor que escribe el usuario (docs/05-app.md §5.1).
///
/// Acepta formas cortas y las completa: `transporte.ejemplo.org` →
/// `https://transporte.ejemplo.org/api/v1`. Sin protocolo se usa HTTPS, el
/// único que admiten las versiones de producción; `http://` hay que escribirlo
/// (solo funciona en las de depuración).
class ServerUrl {
  static const apiPath = '/api/v1';

  /// Devuelve la dirección completa de la API, o null si no es válida.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty || text.contains(' ')) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty || !uri.host.contains(RegExp(r'[.:]|^localhost$'))) {
      return null;
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith(apiPath)) path = '$path$apiPath';
    return uri.replace(path: path, query: null, fragment: null).toString().replaceAll(RegExp(r'[?#]$'), '');
  }

  /// La dirección sin el protocolo ni /api/v1, para mostrarla o compartirla.
  static String short(String url) => url.replaceFirst(RegExp(r'^https://'), '').replaceFirst(RegExp('${RegExp.escape(apiPath)}\$'), '');

}
