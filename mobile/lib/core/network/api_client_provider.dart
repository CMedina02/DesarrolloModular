import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Holds the active bearer token in memory for [ApiClient].
class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setToken(String? token) {
    final trimmed = token?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void clear() {
    state = null;
  }
}

/// Active JWT token read lazily by [apiClientProvider].
final authTokenProvider = NotifierProvider<AuthTokenNotifier, String?>(
  AuthTokenNotifier.new,
);

/// Shared `http.Client` disposed automatically with the Riverpod container.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Root API client configured with [appConfigProvider] and [authTokenProvider].
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final httpClient = ref.watch(httpClientProvider);

  return ApiClient(
    config: config,
    httpClient: httpClient,
    tokenProvider: () => ref.read(authTokenProvider),
  );
});
