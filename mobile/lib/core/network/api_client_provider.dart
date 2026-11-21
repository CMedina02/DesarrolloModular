import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Holds the active bearer token (populated by F03 session state).
final authTokenProvider = Provider<String?>((ref) => null);

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
