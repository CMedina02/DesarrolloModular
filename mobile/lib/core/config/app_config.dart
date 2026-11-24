import 'package:flutter/foundation.dart';

/// Public client configuration injected at build/run time via `--dart-define`.
///
/// Only non-sensitive client settings belong here (never credentials or tokens).
@immutable
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
  });

  static const String defaultApiBaseUrl = 'http://127.0.0.1:3000';
  static const String defaultEnvironment = 'development';
  static const String apiPrefix = '/api/v1';

  final String apiBaseUrl;
  final String environment;

  /// Full base URL including the `/api/v1` prefix (appearing once).
  String get apiBaseWithPrefix => '$apiBaseUrl$apiPrefix';

  /// Reads compile-time environment variables passed via `--dart-define`.
  factory AppConfig.fromEnvironment() {
    const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
    final rawApiBaseUrl = configuredApiBaseUrl.trim().isEmpty && kIsWeb
        ? Uri.base.origin
        : configuredApiBaseUrl;
    const rawEnvironment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: defaultEnvironment,
    );

    return AppConfig.fromValues(
      rawApiBaseUrl: rawApiBaseUrl,
      rawEnvironment: rawEnvironment,
    );
  }

  /// Creates a normalized [AppConfig] from raw string inputs.
  factory AppConfig.fromValues({
    required String rawApiBaseUrl,
    String rawEnvironment = defaultEnvironment,
  }) {
    final normalizedUrl = normalizeBaseUrl(rawApiBaseUrl);
    final trimmedEnv = rawEnvironment.trim();

    return AppConfig(
      apiBaseUrl: normalizedUrl,
      environment: trimmedEnv.isEmpty ? defaultEnvironment : trimmedEnv,
    );
  }

  /// Trims whitespace and removes trailing slashes (and trailing `/api/v1`
  /// if provided) so consumers can safely append routes without duplicating
  /// separators or prefixes.
  static String normalizeBaseUrl(String rawUrl) {
    var value = rawUrl.trim();
    if (value.isEmpty) {
      return defaultApiBaseUrl;
    }

    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    if (value.endsWith(apiPrefix)) {
      value = value.substring(0, value.length - apiPrefix.length);
      while (value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
    }

    return value.isEmpty ? defaultApiBaseUrl : value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          runtimeType == other.runtimeType &&
          apiBaseUrl == other.apiBaseUrl &&
          environment == other.environment;

  @override
  int get hashCode => Object.hash(apiBaseUrl, environment);
}
