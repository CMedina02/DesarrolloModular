import 'package:flutter/foundation.dart';

/// Error payload returned by the backend: `{"error": {"code": "...", "message": "..."}}`.
@immutable
class ApiErrorBody {
  const ApiErrorBody({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  factory ApiErrorBody.fromJson(Map<String, dynamic> json) {
    final errorObj = json['error'];
    if (errorObj is! Map<String, dynamic>) {
      throw const FormatException('Expected "error" object in error response');
    }
    return ApiErrorBody(
      code: errorObj['code'] as String,
      message: errorObj['message'] as String,
    );
  }

  /// Attempts to parse an [ApiErrorBody]; returns `null` if the payload does
  /// not match the standard error envelope.
  static ApiErrorBody? tryParse(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final errorObj = decoded['error'];
    if (errorObj is! Map<String, dynamic>) return null;
    final code = errorObj['code'];
    final message = errorObj['message'];
    if (code is! String || message is! String) return null;
    return ApiErrorBody(code: code, message: message);
  }
}
