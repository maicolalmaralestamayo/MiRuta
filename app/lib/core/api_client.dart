import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'api_exception.dart';
import 'json_api.dart';
import 'storage.dart';
import '../services/installation.dart';

/// Cliente de la API JSON:API. Añade el token de acceso y, si caducó, lo
/// renueva una sola vez (también entre la app y sus tareas en segundo plano,
/// con un bloqueo de archivo) y repite la petición.
class ApiClient {
  static const jsonApi = 'application/vnd.api+json';
  static const atomic = 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"';

  final Dio _dio;

  /// Se llama cuando la sesión ya no es válida (hay que volver a iniciar sesión).
  void Function()? onSessionExpired;

  /// Se llama tras cada petición: true si el servidor respondió (aunque sea
  /// con un error) y false si no se pudo llegar a él. Lo usa el punto de
  /// conexión (services/connection.dart, docs/11 §11.14).
  void Function(bool reachable)? onReachability;

  Future<void>? _refreshing;

  ApiClient._(this._dio) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest));
  }

  /// Para pruebas: un cliente con ese Dio (sin leer la dirección guardada).
  @visibleForTesting
  factory ApiClient.withDio(Dio dio) => ApiClient._(dio);

  static Future<ApiClient> create() async {
    final dio = Dio(BaseOptions(
      baseUrl: await Storage.apiUrl(),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      // La versión instalada: así el Administrador ve quién no ha actualizado.
      headers: {'Accept': jsonApi, 'X-App-Version-Code': (await PackageInfo.fromPlatform()).buildNumber},
      validateStatus: (status) => status != null && status < 400,
    ));
    return ApiClient._(dio);
  }

  void setBaseUrl(String url) => _dio.options.baseUrl = url;

  String get baseUrl => _dio.options.baseUrl;

  /// Si ya se sabe a qué servidor conectarse.
  bool get hasServer => baseUrl.isNotEmpty;

  /// Mensaje cuando no se puede conectar con el servidor (docs/09 §2).
  static const unreachableMessage =
      'Fue imposible conectarse al servidor. Revise el protocolo de conexión que seleccionó, la dirección del servidor que indicó y asegúrese de tener conexión a Internet.';

  /// Comprueba que en [url] responde un servidor de MiRuta y devuelve la
  /// dirección a la que finalmente llegó: si el servidor redirige (p. ej. de
  /// http a https), se sigue la redirección y se devuelve la nueva dirección
  /// para guardarla (docs/09, Generales: certificados).
  static Future<String> probe(String url) async {
    final dio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': jsonApi},
    ));
    const path = '/password-policy';
    try {
      final response = await dio.get<dynamic>(path);
      final data = response.data;
      if (data is! Map || data['data'] is! Map || (data['data'] as Map)['type'] != 'password-policies') throw const FormatException();
      final reached = response.realUri.toString().split('?').first.split('#').first;
      return reached.endsWith(path) ? reached.substring(0, reached.length - path.length) : url;
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) throw _probeError('NETWORK_ERROR', unreachableMessage);
      // Responde la API pero con un error (p. ej. aún sin base de datos): es
      // MiRuta y se acepta, para poder hacer su mantenimiento desde la app.
      final data = response.data;
      if (data is Map && data['errors'] is List && (response.statusCode ?? 0) >= 500) {
        final reached = response.realUri.toString().split('?').first.split('#').first;
        return reached.endsWith(path) ? reached.substring(0, reached.length - path.length) : url;
      }
      throw _probeError('NOT_MITRANSPORTE', 'En esa dirección no hay un servidor de MiRuta.');
    } on FormatException {
      throw _probeError('NOT_MITRANSPORTE', 'En esa dirección no hay un servidor de MiRuta.');
    }
  }

  /// Aún no se ha indicado a qué servidor conectarse.
  static ApiException noServer() =>
      _probeError('NO_SERVER', 'Primero indique la dirección del servidor con el botón «Indicar servidor», al pie de la pantalla de inicio de sesión.');

  static ApiException _probeError(String code, String detail) =>
      ApiException(null, [JsonApiError(status: '', code: code, title: 'Servidor', detail: detail)]);

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] != false) {
      final token = await Storage.accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    // Sin cuenta (o al iniciar sesión) se identifica la instalación.
    if (options.extra['installation'] == true) {
      try {
        options.headers['X-Installation'] = await Installation.ensure(_dio);
      } catch (_) {
        // Sin conexión: la petición fallará igualmente y se informará.
      }
    } else if (options.extra['installation'] == 'ifRegistered') {
      final header = await Installation.header();
      if (header != null) options.headers['X-Installation'] = header;
    }
    if (options.data != null && options.data is! FormData) {
      options.headers['Content-Type'] = options.extra['atomic'] == true ? atomic : jsonApi;
    }
    handler.next(options);
  }

  /// Comprueba si el servidor responde (sin sesión ni instalación). Avisa
  /// con [onReachability].
  Future<bool> ping() async {
    if (!hasServer) return false;
    try {
      await _dio.get('/password-policy', options: Options(extra: {'auth': false}, receiveTimeout: const Duration(seconds: 10)));
      onReachability?.call(true);
      return true;
    } on DioException catch (error) {
      final reachable = error.response != null;
      onReachability?.call(reachable);
      return reachable;
    }
  }

  // Métodos

  /// [headers]: cabeceras extra (p. ej. la clave de mantenimiento; con ellas no se envía la sesión).
  Future<JsonApiDocument> get(String path, {Map<String, dynamic>? query, bool guest = false, Map<String, String>? headers}) async =>
      _document(await _send(() => _dio.get(path,
          queryParameters: query,
          options: guest || headers != null ? Options(headers: headers, extra: {'auth': headers == null && !guest ? true : false, 'installation': guest}) : null)));

  /// Todas las páginas de una colección.
  Future<List<Resource>> getAll(String path, {Map<String, dynamic>? query, int pageSize = 100}) async {
    final resources = <Resource>[];
    var page = 1;
    while (true) {
      final document = await get(path, query: {...?query, 'page[size]': pageSize, 'page[number]': page});
      resources.addAll(document.resources);
      if (!document.hasNext) return resources;
      page++;
    }
  }

  /// [guest]: sin sesión, identificando la instalación (X-Installation).
  /// [withInstallation]: además de la sesión, la instalación (al iniciar
  /// sesión o registrarse, para pasar a la cuenta lo hablado sin ella).
  Future<JsonApiDocument> post(String path, Map<String, dynamic> body, {bool auth = true, bool guest = false, bool withInstallation = false, Map<String, String>? headers}) async =>
      _document(await _send(() => _dio.post(path,
          data: body,
          options: Options(
              headers: headers,
              receiveTimeout: headers != null ? const Duration(minutes: 10) : null,
              extra: {'auth': auth && !guest && headers == null, 'installation': guest ? true : (withInstallation ? 'ifRegistered' : false)}))));

  Future<JsonApiDocument> patch(String path, Map<String, dynamic> body) async =>
      _document(await _send(() => _dio.patch(path, data: body)));

  Future<void> delete(String path) async => _send(() => _dio.delete(path));

  /// Operaciones atómicas (JSON:API Atomic Operations).
  Future<List<Resource>> atomicOperations(List<Map<String, dynamic>> operations) async {
    final response = await _send(() => _dio.post('/operations', data: {'atomic:operations': operations}, options: Options(extra: {'atomic': true})));
    final results = (response.data is Map ? response.data['atomic:results'] as List? : null) ?? const [];
    return results
        .where((result) => result is Map && result['data'] != null)
        .map((result) => Resource.fromJson(Map<String, dynamic>.from(result['data'] as Map)))
        .toList();
  }

  /// Subida de un archivo (multipart/form-data), con otros campos opcionales.
  Future<JsonApiDocument> upload(String path, String field, String filePath, {Map<String, dynamic> fields = const {}, void Function(int sent, int total)? onProgress}) =>
      uploadFiles(path, {field: filePath}, fields: fields, onProgress: onProgress);

  /// Varios archivos en una sola petición multipart ({campo: ruta}).
  Future<JsonApiDocument> uploadFiles(String path, Map<String, String> files, {Map<String, dynamic> fields = const {}, void Function(int sent, int total)? onProgress}) async {
    return _document(await _send(() async => _dio.post(
          path,
          data: FormData.fromMap({
            ...fields,
            for (final entry in files.entries) entry.key: await MultipartFile.fromFile(entry.value),
          }),
          options: Options(sendTimeout: const Duration(minutes: 30), receiveTimeout: const Duration(minutes: 5)),
          onSendProgress: onProgress,
        )));
  }

  // Envío con renovación de token

  Future<Response> _send(Future<Response> Function() request, {bool retried = false}) async {
    if (!hasServer) throw noServer();
    try {
      final response = await request();
      onReachability?.call(true);
      return response;
    } on DioException catch (error) {
      onReachability?.call(error.response != null);
      final apiError = _toApiException(error);
      if (!retried && apiError.statusCode == 401 && apiError.hasCode('TOKEN_EXPIRED')) {
        await refreshTokens();
        return _send(request, retried: true);
      }
      if (apiError.statusCode == 401 && (apiError.hasCode('TOKEN_REVOKED') || apiError.hasCode('TOKEN_INVALID'))) {
        onSessionExpired?.call();
      }
      throw apiError;
    }
  }

  /// Renueva los tokens. Un solo intento a la vez, en todo el teléfono.
  Future<void> refreshTokens() {
    return _refreshing ??= _refreshWithLock().whenComplete(() => _refreshing = null);
  }

  Future<void> _refreshWithLock() async {
    final usedAccess = await Storage.accessToken();
    final lockFile = File('${(await getApplicationSupportDirectory()).path}/token.lock');
    final lock = await lockFile.open(mode: FileMode.write);
    await lock.lock(FileLock.blockingExclusive);
    try {
      // Otro proceso pudo renovarlos mientras esperábamos el bloqueo.
      if (await Storage.accessToken() != usedAccess) return;

      final refresh = await Storage.refreshToken();
      if (refresh == null) throw _expired();

      try {
        final response = await _dio.post('/tokens/refresh',
            data: resourceData('tokens', attributes: {'refreshToken': refresh}), options: Options(extra: {'auth': false}));
        final attributes = _document(response).resource.attributes;
        await Storage.saveTokens(attributes['accessToken'] as String, attributes['refreshToken'] as String);
      } on DioException catch (error) {
        final apiError = _toApiException(error);
        if (apiError.statusCode == 401) {
          await Storage.clearTokens();
          onSessionExpired?.call();
        }
        throw apiError;
      }
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  ApiException _expired() => ApiException(401, [JsonApiError(status: '401', code: 'TOKEN_REVOKED', title: 'Sesión cerrada', detail: 'Inicia sesión de nuevo.')]);

  JsonApiDocument _document(Response response) {
    final data = response.data;
    return JsonApiDocument.fromJson(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  ApiException _toApiException(DioException error) {
    final response = error.response;
    if (response == null) return ApiException.network();
    final data = response.data;
    final errors = data is Map && data['errors'] is List
        ? (data['errors'] as List).map((item) => JsonApiError.fromJson(Map<String, dynamic>.from(item as Map))).toList()
        : [JsonApiError(status: '${response.statusCode}', code: 'HTTP_${response.statusCode}', title: 'Error del servidor (${response.statusCode})')];
    return ApiException(response.statusCode, errors);
  }
}
