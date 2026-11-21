import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/application/auth_state.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

Map<String, dynamic> _userJson({
  required String role,
  String? businessId,
  String email = 'user@demo.local',
}) {
  return {
    'id': '44444444-4444-4444-8444-444444444444',
    'business_id': businessId,
    'name': 'Usuario $role',
    'email': email,
    'role': role,
    'is_active': true,
    'created_at': '2026-11-20T18:00:00Z',
    'updated_at': '2026-11-20T18:00:00Z',
  };
}

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  group('AuthController', () {
    test('restaura sesión válida con GET /auth/me usando el token guardado', () async {
      late String? sentAuth;
      final storage = InMemoryTokenStorage(initialToken: 'saved-jwt-token');
      final mockClient = MockClient((request) async {
        sentAuth = request.headers['Authorization'];
        expect(request.url.path, '/api/v1/auth/me');
        return http.Response(
          jsonEncode(
            _userJson(
              role: 'ADMIN',
              businessId: '22222222-2222-4222-8222-222222222222',
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).restoreSession();

      final state = container.read(authControllerProvider);
      expect(sentAuth, 'Bearer saved-jwt-token');
      expect(state.status, AuthStatus.authenticated);
      expect(state.role, UserRole.admin);
      expect(state.businessId, '22222222-2222-4222-8222-222222222222');
    });

    test('limpia token y vuelve a unauthenticated ante 401 al restaurar', () async {
      final storage = InMemoryTokenStorage(initialToken: 'expired-jwt');
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Token inválido',
            },
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).restoreSession();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, isNotNull);
      expect(await storage.readToken(), isNull);
      expect(container.read(authTokenProvider), isNull);
    });

    test('expira sesión tras 900 segundos con reloj controlado', () async {
      var now = DateTime.utc(2026, 11, 20, 20, 0, 0);
      final storage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'jwt-900s',
            'token_type': 'Bearer',
            'expires_in': 900,
            'user': _userJson(
              role: 'EMPLOYEE',
              businessId: '22222222-2222-4222-8222-222222222222',
            ),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(storage),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container.read(authControllerProvider.notifier).login(
            email: 'emp@demo.local',
            password: 'password-demo-123',
          );
      expect(ok, isTrue);
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      now = now.add(const Duration(seconds: 901));
      final expired =
          await container.read(authControllerProvider.notifier).checkExpiration();

      expect(expired, isTrue);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, contains('900'));
      expect(await storage.readToken(), isNull);
      expect(container.read(authTokenProvider), isNull);
    });

    test('maneja 429 Too Many Requests con Retry-After', () async {
      final storage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'TOO_MANY_REQUESTS',
              'message': 'Demasiados intentos.',
            },
          }),
          429,
          headers: {
            'content-type': 'application/json',
            'Retry-After': '30',
          },
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container.read(authControllerProvider.notifier).login(
            email: 'admin@demo.local',
            password: 'wrong',
          );

      final state = container.read(authControllerProvider);
      expect(ok, isFalse);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.retryAfterSeconds, 30);
      expect(state.errorMessage, contains('30'));
    });

    test('evita envíos duplicados mientras hay un login pendiente', () async {
      var requestCount = 0;
      final completer = Completer<http.Response>();

      final mockClient = MockClient((request) {
        requestCount++;
        return completer.future;
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authControllerProvider.notifier);
      final first = notifier.login(email: 'a@b.com', password: 'secret');
      final second = notifier.login(email: 'a@b.com', password: 'secret');

      expect(await second, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(requestCount, 1);

      completer.complete(
        http.Response(
          jsonEncode({
            'access_token': 'tok-1',
            'token_type': 'Bearer',
            'expires_in': 900,
            'user': _userJson(role: 'PLATFORM_ADMIN', businessId: null),
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(await first, isTrue);
      expect(requestCount, 1);
      expect(container.read(authControllerProvider).isPlatformAdmin, isTrue);
      expect(container.read(authControllerProvider).businessId, isNull);
    });

    test('logout limpia token persistido y perfil en memoria', () async {
      final storage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'tok-logout',
            'token_type': 'Bearer',
            'expires_in': 900,
            'user': _userJson(
              role: 'ADMIN',
              businessId: '22222222-2222-4222-8222-222222222222',
            ),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(mockClient),
          tokenStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'admin@demo.local',
            password: 'secret',
          );
      expect(await storage.readToken(), 'tok-logout');

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(container.read(authControllerProvider).user, isNull);
      expect(container.read(authTokenProvider), isNull);
      expect(await storage.readToken(), isNull);
    });
  });
}
