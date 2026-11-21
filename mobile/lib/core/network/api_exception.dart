import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/api_error_body.dart';

/// Semantic category for API, HTTP, timeout, and network failures.
enum ApiErrorKind {
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  payloadTooLarge,
  unsupportedMediaType,
  tooManyRequests,
  serverError,
  timeout,
  network,
  invalidResponse,
  unknown,
}

/// Structured exception thrown by [ApiClient].
///
/// Preserves HTTP status semantics and server `error.code` while providing
/// a user-facing message. Never stores tokens, passwords, or auth headers.
@immutable
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.code,
    required this.message,
    required this.userMessage,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final ApiErrorKind kind;
  final int? statusCode;
  final String code;
  final String message;
  final String userMessage;
  final int? retryAfterSeconds;

  bool get isAuthFailure => kind == ApiErrorKind.unauthorized;
  bool get isForbidden => kind == ApiErrorKind.forbidden;
  bool get isConflict => kind == ApiErrorKind.conflict;
  bool get isRateLimited => kind == ApiErrorKind.tooManyRequests;
  bool get isConnectivityIssue =>
      kind == ApiErrorKind.timeout || kind == ApiErrorKind.network;

  factory ApiException.timeout() {
    return const ApiException(
      kind: ApiErrorKind.timeout,
      code: 'TIMEOUT',
      message: 'Request timed out.',
      userMessage:
          'La solicitud tardó demasiado en responder. Verifica tu conexión e inténtalo de nuevo.',
    );
  }

  factory ApiException.network() {
    return const ApiException(
      kind: ApiErrorKind.network,
      code: 'NETWORK_ERROR',
      message: 'Network error while reaching the server.',
      userMessage:
          'No se pudo conectar con el servidor. Revisa tu red y la URL configurada.',
    );
  }

  factory ApiException.invalidResponse({int? statusCode}) {
    return ApiException(
      kind: ApiErrorKind.invalidResponse,
      statusCode: statusCode,
      code: 'INVALID_RESPONSE',
      message: 'The server returned an unexpected response format.',
      userMessage: 'La respuesta del servidor no tiene un formato válido.',
    );
  }

  factory ApiException.fromHttpResponse({
    required int statusCode,
    ApiErrorBody? errorBody,
    int? retryAfterSeconds,
  }) {
    final kind = ApiErrorTranslator.kindFromStatusCode(statusCode);
    final code = errorBody?.code ?? ApiErrorTranslator.defaultCodeForKind(kind);
    final serverMessage = errorBody?.message ?? '';
    final userMessage = ApiErrorTranslator.translate(
      kind: kind,
      code: code,
      serverMessage: serverMessage,
      retryAfterSeconds: retryAfterSeconds,
    );

    return ApiException(
      kind: kind,
      statusCode: statusCode,
      code: code,
      message: serverMessage.isNotEmpty ? serverMessage : userMessage,
      userMessage: userMessage,
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  @override
  String toString() =>
      'ApiException(kind: $kind, statusCode: $statusCode, code: $code, '
      'retryAfterSeconds: $retryAfterSeconds)';
}

/// Translates HTTP status codes and server `error.code` values into clear,
/// consistent Spanish messages for the UI.
abstract final class ApiErrorTranslator {
  static ApiErrorKind kindFromStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return ApiErrorKind.badRequest;
      case 401:
        return ApiErrorKind.unauthorized;
      case 403:
        return ApiErrorKind.forbidden;
      case 404:
        return ApiErrorKind.notFound;
      case 409:
        return ApiErrorKind.conflict;
      case 413:
        return ApiErrorKind.payloadTooLarge;
      case 415:
        return ApiErrorKind.unsupportedMediaType;
      case 429:
        return ApiErrorKind.tooManyRequests;
      default:
        if (statusCode >= 500 && statusCode <= 599) {
          return ApiErrorKind.serverError;
        }
        return ApiErrorKind.unknown;
    }
  }

  static String defaultCodeForKind(ApiErrorKind kind) {
    switch (kind) {
      case ApiErrorKind.badRequest:
        return 'VALIDATION_ERROR';
      case ApiErrorKind.unauthorized:
        return 'UNAUTHENTICATED';
      case ApiErrorKind.forbidden:
        return 'FORBIDDEN';
      case ApiErrorKind.notFound:
        return 'NOT_FOUND';
      case ApiErrorKind.conflict:
        return 'CONFLICT';
      case ApiErrorKind.payloadTooLarge:
        return 'PAYLOAD_TOO_LARGE';
      case ApiErrorKind.unsupportedMediaType:
        return 'UNSUPPORTED_MEDIA_TYPE';
      case ApiErrorKind.tooManyRequests:
        return 'TOO_MANY_REQUESTS';
      case ApiErrorKind.serverError:
        return 'INTERNAL_ERROR';
      case ApiErrorKind.timeout:
        return 'TIMEOUT';
      case ApiErrorKind.network:
        return 'NETWORK_ERROR';
      case ApiErrorKind.invalidResponse:
        return 'INVALID_RESPONSE';
      case ApiErrorKind.unknown:
        return 'UNKNOWN_ERROR';
    }
  }

  static String translate({
    required ApiErrorKind kind,
    required String code,
    required String serverMessage,
    int? retryAfterSeconds,
  }) {
    if (kind == ApiErrorKind.tooManyRequests || code == 'TOO_MANY_REQUESTS') {
      if (retryAfterSeconds != null && retryAfterSeconds > 0) {
        return 'Demasiados intentos. Vuelve a intentarlo en $retryAfterSeconds segundos.';
      }
      return 'Demasiados intentos. Vuelve a intentarlo más tarde.';
    }

    switch (code) {
      case 'VALIDATION_ERROR':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'Revisa los datos ingresados en el formulario.';
      case 'UNAUTHENTICATED':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'Credenciales inválidas o sesión expirada.';
      case 'FORBIDDEN':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'No tienes permiso para realizar esta operación o el módulo está deshabilitado.';
      case 'MODULE_DISABLED':
        return 'El módulo de Inventario está deshabilitado para esta empresa.';
      case 'NOT_FOUND':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'No se encontró el recurso solicitado.';
      case 'CONFLICT':
        return serverMessage.isNotEmpty
            ? serverMessage
            : 'La operación entra en conflicto con el estado actual de los datos.';
      case 'INSUFFICIENT_STOCK':
        return 'No hay existencias suficientes para completar la salida.';
      case 'PAYLOAD_TOO_LARGE':
        return 'Los datos enviados superan el tamaño máximo permitido.';
      case 'UNSUPPORTED_MEDIA_TYPE':
        return 'El formato de la solicitud no es compatible.';
      case 'INTERNAL_ERROR':
        return 'Ocurrió un error interno en el servidor. Inténtalo de nuevo.';
    }

    if (serverMessage.isNotEmpty) {
      return serverMessage;
    }

    switch (kind) {
      case ApiErrorKind.badRequest:
        return 'Solicitud inválida. Revisa los datos enviados.';
      case ApiErrorKind.unauthorized:
        return 'Credenciales inválidas o sesión expirada.';
      case ApiErrorKind.forbidden:
        return 'La operación no está permitida para tu sesión.';
      case ApiErrorKind.notFound:
        return 'No se encontró el recurso solicitado.';
      case ApiErrorKind.conflict:
        return 'Conflicto con el estado actual de los datos.';
      case ApiErrorKind.payloadTooLarge:
        return 'El cuerpo de la solicitud es demasiado grande.';
      case ApiErrorKind.unsupportedMediaType:
        return 'Formato de solicitud no admitido.';
      case ApiErrorKind.tooManyRequests:
        return 'Demasiados intentos. Vuelve a intentarlo más tarde.';
      case ApiErrorKind.serverError:
        return 'Error interno del servidor. Inténtalo más tarde.';
      case ApiErrorKind.timeout:
        return 'La solicitud excedió el tiempo de espera.';
      case ApiErrorKind.network:
        return 'No se pudo conectar con el servidor.';
      case ApiErrorKind.invalidResponse:
        return 'La respuesta del servidor no es válida.';
      case ApiErrorKind.unknown:
        return 'No se pudo completar la operación.';
    }
  }
}
