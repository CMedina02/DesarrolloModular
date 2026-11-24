import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/network/api_client.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';

void main() {
  final defaultConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000/',
  );

  group('ApiClient URL building & transport', () {
    test('construye ruta pública POST /auth/login sin Bearer y con prefijo único', () async {
      late http.Request captured;

      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'access_token': 'tok-123',
            'token_type': 'Bearer',
            'expires_in': 900,
            'user': {
              'id': '44444444-4444-4444-8444-444444444444',
              'business_id': '22222222-2222-4222-8222-222222222222',
              'name': 'Admin Demo',
              'email': 'admin@demo.local',
              'role': 'ADMIN',
              'is_active': true,
              'created_at': '2026-11-20T18:00:00Z',
              'updated_at': '2026-11-20T18:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(
        config: defaultConfig,
        httpClient: mockClient,
        tokenProvider: () => 'existing-token',
      );

      final result = await api.postJson(
        '/api/v1/auth/login',
        body: {'email': 'admin@demo.local', 'password': 'secret'},
        authenticated: false,
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'http://127.0.0.1:3000/api/v1/auth/login');
      expect(captured.headers['Accept'], 'application/json');
      expect(
        captured.headers['Content-Type'],
        contains('application/json'),
      );
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(captured.body), {
        'email': 'admin@demo.local',
        'password': 'secret',
      });
      expect(result['token_type'], 'Bearer');
    });

    test('construye ruta protegida GET con Bearer y query params', () async {
      late http.Request captured;

      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(
        config: defaultConfig,
        httpClient: mockClient,
        tokenProvider: () => 'jwt-token-xyz',
      );

      await api.getJson(
        '/businesses/22222222-2222-4222-8222-222222222222/inventory/products',
        queryParameters: {'limit': 25, 'offset': 0, 'low_stock': true, 'ignored': null},
      );

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'http://127.0.0.1:3000/api/v1/businesses/22222222-2222-4222-8222-222222222222/inventory/products?limit=25&offset=0&low_stock=true',
      );
      expect(captured.headers['Authorization'], 'Bearer jwt-token-xyz');
      expect(captured.headers['Accept'], 'application/json');
    });

    test('procesa 204 No Content sin intentar decodificar JSON', () async {
      late http.Request captured;

      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });

      final api = ApiClient(
        config: defaultConfig,
        httpClient: mockClient,
        tokenProvider: () => 'jwt-token-xyz',
      );

      await expectLater(
        api.deleteNoContent(
          '/businesses/22222222-2222-4222-8222-222222222222/inventory/categories/33333333-3333-4333-8333-333333333333',
        ),
        completes,
      );

      expect(captured.method, 'DELETE');
      expect(captured.headers['Authorization'], 'Bearer jwt-token-xyz');
    });

    test('checkHealth consulta GET /health fuera del prefijo /api/v1', () async {
      late http.Request captured;

      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'status': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(
        config: defaultConfig,
        httpClient: mockClient,
        tokenProvider: () => 'should-not-be-sent',
      );

      final health = await api.checkHealth();

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://127.0.0.1:3000/health');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(health.isHealthy, isTrue);
      expect(health.status, 'ok');
    });
  });

  group('ApiClient error handling', () {
    final cases = <(int, String, ApiErrorKind)>[
      (400, 'VALIDATION_ERROR', ApiErrorKind.badRequest),
      (401, 'UNAUTHENTICATED', ApiErrorKind.unauthorized),
      (403, 'FORBIDDEN', ApiErrorKind.forbidden),
      (404, 'NOT_FOUND', ApiErrorKind.notFound),
      (409, 'CONFLICT', ApiErrorKind.conflict),
      (429, 'TOO_MANY_REQUESTS', ApiErrorKind.tooManyRequests),
    ];

    for (final (status, code, expectedKind) in cases) {
      test('distingue estado HTTP $status ($code)', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': code,
                'message': 'Detalle del servidor para $status',
              },
            }),
            status,
            headers: {
              'content-type': 'application/json',
              if (status == 429) 'Retry-After': '45',
            },
          );
        });

        final api = ApiClient(config: defaultConfig, httpClient: mockClient);

        try {
          await api.getJson('/auth/me');
          fail('Se esperaba ApiException para HTTP $status');
        } on ApiException catch (e) {
          expect(e.statusCode, status);
          expect(e.kind, expectedKind);
          expect(e.code, code);
          expect(e.userMessage, isNotEmpty);
          if (status == 429) {
            expect(e.retryAfterSeconds, 45);
            expect(e.isRateLimited, isTrue);
            expect(e.userMessage, contains('45'));
          }
        }
      });
    }

    test('distingue tiempo de espera (TimeoutException)', () async {
      final mockClient = MockClient((request) async {
        throw TimeoutException('Simulated timeout');
      });

      final api = ApiClient(config: defaultConfig, httpClient: mockClient);

      expect(
        () => api.getJson('/auth/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
              .having((e) => e.isConnectivityIssue, 'isConnectivityIssue', isTrue)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('distingue falta de red (ClientException)', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Failed host lookup');
      });

      final api = ApiClient(config: defaultConfig, httpClient: mockClient);

      expect(
        () => api.getJson('/auth/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network)
              .having((e) => e.isConnectivityIssue, 'isConnectivityIssue', isTrue)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });
  });
}
