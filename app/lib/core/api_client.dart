import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'api_exception.dart';
import 'json_api.dart';
import 'storage.dart';

/// Cliente de la API JSON:API. Añade el token de acceso y, si caducó, lo
/// renueva una sola vez (también entre la app y sus tareas en segundo plano,
/// con un bloqueo de archivo) y repite la petición.
class ApiClient {
  static const jsonApi = 'application/vnd.api+json';
  static const atomic = 'application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"';

  final Dio _dio;

  /// Se llama cuando la sesión ya no es válida (hay que volver a iniciar sesión).
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  ApiClient._(this._dio) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest));
  }

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

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] != false) {
      final token = await Storage.accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    if (options.data != null && options.data is! FormData) {
      options.headers['Content-Type'] = options.extra['atomic'] == true ? atomic : jsonApi;
    }
    handler.next(options);
  }

  // Métodos

  Future<JsonApiDocument> get(String path, {Map<String, dynamic>? query}) async =>
      _document(await _send(() => _dio.get(path, queryParameters: query)));

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

  Future<JsonApiDocument> post(String path, Map<String, dynamic> body, {bool auth = true}) async =>
      _document(await _send(() => _dio.post(path, data: body, options: Options(extra: {'auth': auth}))));

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
  Future<JsonApiDocument> upload(String path, String field, String filePath, {Map<String, dynamic> fields = const {}, void Function(int sent, int total)? onProgress}) async {
    return _document(await _send(() async => _dio.post(
          path,
          data: FormData.fromMap({...fields, field: await MultipartFile.fromFile(filePath)}),
          options: Options(sendTimeout: const Duration(minutes: 30), receiveTimeout: const Duration(minutes: 5)),
          onSendProgress: onProgress,
        )));
  }

  // Envío con renovación de token

  Future<Response> _send(Future<Response> Function() request, {bool retried = false}) async {
    try {
      return await request();
    } on DioException catch (error) {
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
