/// Dirección del servidor (docs/09-repaso-pantallas.md §2).
///
/// El usuario elige el protocolo (https por defecto, o http) y escribe la
/// dirección; no se prueban protocolos automáticamente. La app completa la
/// ruta de la API: https + `transporte.ejemplo.org` →
/// `https://transporte.ejemplo.org/api/v1`.
class ServerUrl {
  static const apiPath = '/api/v1';
  static const protocols = ['https', 'http'];
  static const defaultProtocol = 'https';

  /// Separa una dirección escrita o pegada en su protocolo (null si no lo
  /// trae, o si no es http/https) y la dirección sin protocolo ni /api/v1.
  static ({String? protocol, String address}) split(String input) {
    var text = input.trim();
    String? protocol;
    final match = RegExp(r'^(https?)://', caseSensitive: false).firstMatch(text);
    if (match != null) {
      protocol = match.group(1)!.toLowerCase();
      text = text.substring(match.end);
    }
    text = text.replaceAll(RegExp(r'/+$'), '');
    if (text.endsWith(apiPath)) text = text.substring(0, text.length - apiPath.length);
    return (protocol: protocol, address: text.replaceAll(RegExp(r'/+$'), ''));
  }

  /// URL completa de la API a partir del protocolo y la dirección; null si
  /// la dirección no es válida. Si la dirección trae su propio protocolo,
  /// manda el que trae.
  static String? build(String protocol, String address) {
    final parts = split(address);
    if (parts.address.isEmpty || parts.address.contains(' ') || parts.address.contains('://')) return null;
    final scheme = parts.protocol ?? protocol.toLowerCase();
    if (!protocols.contains(scheme)) return null;
    return _complete('$scheme://${parts.address}');
  }

  /// URL completa de una dirección escrita de una vez (con o sin protocolo;
  /// sin él, https).
  static String? fromInput(String input) => build(split(input).protocol ?? defaultProtocol, input);

  /// Compatibilidad: la única dirección posible, o vacía si no es válida.
  static List<String> candidates(String input) => [?fromInput(input)];

  static bool isValid(String address, {String protocol = defaultProtocol}) => build(protocol, address) != null;

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
