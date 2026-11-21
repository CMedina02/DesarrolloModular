import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/models/api_error_body.dart';
import 'package:inventario_comercial/core/models/health_status.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';

typedef TokenProvider = String? Function();

/// Common HTTP/JSON transport for DesarrolloModular API.
///
/// Centralizes base URL resolution, the `/api/v1` prefix, `Authorization`
/// Bearer headers, empty `204` responses, timeouts, and error translation.
class ApiClient {
  ApiClient({
    required this._config,
    http.Client? httpClient,
    this._tokenProvider,
    this._timeout = defaultTimeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const Duration defaultTimeout = Duration(seconds: 15);

  final AppConfig _config;
  final http.Client _httpClient;
  final bool _ownsClient;
  final TokenProvider? _tokenProvider;
  final Duration _timeout;

  /// Builds a URI under `/api/v1`, guaranteeing the prefix appears once.
  Uri buildApiUri(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    var cleanPath = path.trim();
    if (!cleanPath.startsWith('/')) {
      cleanPath = '/$cleanPath';
    }
    if (cleanPath == AppConfig.apiPrefix) {
      cleanPath = '';
    } else if (cleanPath.startsWith('${AppConfig.apiPrefix}/')) {
      cleanPath = cleanPath.substring(AppConfig.apiPrefix.length);
    }

    final fullUrl = '${_config.apiBaseWithPrefix}$cleanPath';
    return _attachQuery(Uri.parse(fullUrl), queryParameters);
  }

  /// Builds a URI directly on the server root (outside `/api/v1`), e.g. `/health`.
  Uri buildRootUri(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    var cleanPath = path.trim();
    if (!cleanPath.startsWith('/')) {
      cleanPath = '/$cleanPath';
    }
    final fullUrl = '${_config.apiBaseUrl}$cleanPath';
    return _attachQuery(Uri.parse(fullUrl), queryParameters);
  }

  /// Checks server health via `GET /health` outside `/api/v1`.
  Future<HealthStatus> checkHealth() async {
    final decoded = await _send(
      method: 'GET',
      uri: buildRootUri('/health'),
      authenticated: false,
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return HealthStatus.fromJson(decoded);
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      method: 'GET',
      uri: buildApiUri(path, queryParameters: queryParameters),
      authenticated: authenticated,
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return decoded;
  }

  Future<List<dynamic>> getJsonList(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      method: 'GET',
      uri: buildApiUri(path, queryParameters: queryParameters),
      authenticated: authenticated,
    );
    if (decoded is! List<dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      method: 'POST',
      uri: buildApiUri(path),
      body: body,
      authenticated: authenticated,
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      method: 'PUT',
      uri: buildApiUri(path),
      body: body,
      authenticated: authenticated,
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      method: 'PATCH',
      uri: buildApiUri(path),
      body: body,
      authenticated: authenticated,
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.invalidResponse(statusCode: 200);
    }
    return decoded;
  }

  /// Sends a `DELETE` request expecting `204 No Content` (no JSON body).
  Future<void> deleteNoContent(
    String path, {
    bool authenticated = true,
  }) async {
    await _send(
      method: 'DELETE',
      uri: buildApiUri(path),
      authenticated: authenticated,
    );
  }

  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  Future<Object?> _send({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    required bool authenticated,
  }) async {
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';

    if (authenticated) {
      final token = _tokenProvider?.call()?.trim();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    }

    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    late final http.Response response;
    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    final statusCode = response.statusCode;

    if (statusCode == 204) {
      return null;
    }

    final decodedBody = _tryDecodeBody(response.bodyBytes);

    if (statusCode >= 200 && statusCode < 300) {
      if (response.bodyBytes.isEmpty) {
        return null;
      }
      if (decodedBody == null) {
        throw ApiException.invalidResponse(statusCode: statusCode);
      }
      return decodedBody;
    }

    final errorBody = ApiErrorBody.tryParse(decodedBody);
    final retryAfter = _parseRetryAfter(response.headers);

    throw ApiException.fromHttpResponse(
      statusCode: statusCode,
      errorBody: errorBody,
      retryAfterSeconds: retryAfter,
    );
  }

  Uri _attachQuery(Uri uri, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    final stringParams = <String, String>{};
    queryParameters.forEach((key, value) {
      if (value != null) {
        stringParams[key] = value.toString();
      }
    });

    if (stringParams.isEmpty) {
      return uri;
    }

    return uri.replace(queryParameters: stringParams);
  }

  Object? _tryDecodeBody(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      final text = utf8.decode(bodyBytes);
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  int? _parseRetryAfter(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        return int.tryParse(entry.value.trim());
      }
    }
    return null;
  }
}
