/// Dirección del servidor que escribe el usuario (docs/05-app.md §5.2).
///
/// La app no impone el protocolo: sirve igual con `https://` que con
/// `http://`. Si el usuario no lo escribe, se prueba primero HTTPS y, si ahí
/// no responde, HTTP. También completa la ruta de la API: `transporte.ejemplo.org`
/// → `https://transporte.ejemplo.org/api/v1`.
class ServerUrl {
  static const apiPath = '/api/v1';

  /// Direcciones completas a probar, por orden; vacía si no es válida.
  static List<String> candidates(String input) {
    final text = input.trim();
    if (text.isEmpty || text.contains(' ')) return const [];
    if (text.contains('://')) {
      final url = _complete(text);
      return url == null ? const [] : [url];
    }
    return [for (final scheme in const ['https', 'http']) _complete('$scheme://$text')].whereType<String>().toList();
  }

  static bool isValid(String input) => candidates(input).isNotEmpty;

  /// Si la conexión va sin cifrar.
  static bool isPlain(String url) => url.startsWith('http://');

  /// La dirección sin /api/v1 (y sin https://), para mostrarla o compartirla.
  static String short(String url) => url.replaceFirst(RegExp(r'^https://'), '').replaceFirst(RegExp('${RegExp.escape(apiPath)}\$'), '');

  static String? _complete(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty || !uri.host.contains(RegExp(r'[.:]|^localhost$'))) {
      return null;
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith(apiPath)) path = '$path$apiPath';
    return uri.replace(path: path, query: null, fragment: null).toString().replaceAll(RegExp(r'[?#]$'), '');
  }
}
