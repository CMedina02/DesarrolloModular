import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_comercial/app/app.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const bizB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  Future<void> pumpLoggedInApp(
    WidgetTester tester, {
    required http.Client client,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(client),
          tokenStorageProvider.overrideWithValue(
            InMemoryTokenStorage(initialToken: 'active-jwt'),
          ),
        ],
        child: const InventarioComercialApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('F04: Administración de empresas, usuarios y módulos', () {
    testWidgets(
      'PLATFORM_ADMIN crea empresa y activa Inventario sin afectar otra empresa',
      (tester) async {
        final businesses = <Map<String, dynamic>>[
          {
            'id': bizB,
            'name': 'Comercio Beta',
            'is_active': true,
            'created_at': '2026-11-20T18:00:00Z',
            'updated_at': '2026-11-20T18:00:00Z',
          },
        ];
        final moduleStates = <String, bool>{
          bizA: false,
          bizB: false,
        };

        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '11111111-1111-4111-8111-111111111111',
                'business_id': null,
                'name': 'Root Admin',
                'email': 'root@demo.local',
                'role': 'PLATFORM_ADMIN',
                'is_active': true,
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'items': businesses,
                'limit': 25,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final created = {
              'id': bizA,
              'name': body['name'],
              'is_active': body['is_active'] ?? true,
              'created_at': '2026-11-20T19:00:00Z',
              'updated_at': '2026-11-20T19:00:00Z',
            };
            businesses.add(created);
            return http.Response(
              jsonEncode(created),
              201,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses/$bizA/modules' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode([
                {'key': 'inventory', 'enabled': moduleStates[bizA]},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path ==
                  '/api/v1/businesses/$bizA/modules/inventory' &&
              request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            moduleStates[bizA] = body['enabled'] as bool;
            return http.Response(
              jsonEncode({'key': 'inventory', 'enabled': moduleStates[bizA]}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('Not found', 404);
        });

        await pumpLoggedInApp(tester, client: client);

        expect(find.text('Comercio Beta'), findsOneWidget);

        // Create new business "Comercio Alfa"
        await tester.tap(find.byKey(const Key('create_business_fab')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('business_name_field')),
          'Comercio Alfa',
        );
        await tester.tap(find.byKey(const Key('business_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Comercio Alfa'), findsOneWidget);

        // Navigate to Módulos tab and enable inventory for Comercio Alfa
        await tester.tap(find.text('Módulos'));
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const Key('inventory_module_switch'));
        expect(switchFinder, findsOneWidget);
        expect(moduleStates[bizA], isFalse);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(moduleStates[bizA], isTrue);
        expect(moduleStates[bizB], isFalse);
      },
    );

    testWidgets(
      'ADMIN lista empleados, crea EMPLOYEE y el cliente bloquea asignar ADMIN',
      (tester) async {
        final users = <Map<String, dynamic>>[
          {
            'id': '33333333-3333-4333-8333-333333333333',
            'business_id': bizA,
            'name': 'Empleado Uno',
            'email': 'emp1@alfa.local',
            'role': 'EMPLOYEE',
            'is_active': true,
            'created_at': '2026-11-20T18:00:00Z',
            'updated_at': '2026-11-20T18:00:00Z',
          },
        ];

        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '22222222-2222-4222-8222-222222222222',
                'business_id': bizA,
                'name': 'Admin Alfa',
                'email': 'admin@alfa.local',
                'role': 'ADMIN',
                'is_active': true,
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses/$bizA/modules') {
            return http.Response(
              jsonEncode([
                {'key': 'inventory', 'enabled': true},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses/$bizA/users' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': users, 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/api/v1/businesses/$bizA/users' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['role'], 'EMPLOYEE');
            final created = {
              'id': '55555555-5555-4555-8555-555555555555',
              'business_id': bizA,
              'name': body['name'],
              'email': body['email'],
              'role': body['role'],
              'is_active': true,
              'created_at': '2026-11-20T19:00:00Z',
              'updated_at': '2026-11-20T19:00:00Z',
            };
            users.add(created);
            return http.Response(
              jsonEncode(created),
              201,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('Not found', 404);
        });

        await pumpLoggedInApp(tester, client: client);

        // Navigate to Empleados
        await tester.tap(find.text('Empleados'));
        await tester.pumpAndSettle();

        expect(find.text('Empleado Uno'), findsOneWidget);

        // Open create employee form
        await tester.tap(find.byKey(const Key('create_user_fab')));
        await tester.pumpAndSettle();

        // Client locks role to EMPLOYEE only (helper text shown, ADMIN not offered)
        expect(
          find.text('Solo PLATFORM_ADMIN puede asignar el rol ADMIN.'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('user_name_field')),
          'Empleado Dos',
        );
        await tester.enterText(
          find.byKey(const Key('user_email_field')),
          'emp2@alfa.local',
        );
        await tester.enterText(
          find.byKey(const Key('user_password_field')),
          '🔒' * 7,
        );
        await tester.tap(find.byKey(const Key('user_save_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('La contraseña debe tener al menos 8 caracteres.'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('user_password_field')),
          '🔒' * 8,
        );
        await tester.tap(find.byKey(const Key('user_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Empleado Dos'), findsOneWidget);
      },
    );

    test('servidor devuelve 403 si ADMIN intenta crear rol ADMIN directo', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'FORBIDDEN',
              'message': 'ADMIN solo puede gestionar cuentas EMPLOYEE.',
            },
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(adminRepositoryProvider).createUser(
              bizA,
              const UserCreateRequest(
                name: 'Intento Admin',
                email: 'otro@alfa.local',
                role: UserRole.admin,
                password: 'PasswordSeguro12345!',
              ),
            ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.isForbidden, 'isForbidden', isTrue),
        ),
      );
    });

    testWidgets(
      'EMPLOYEE ve estado deshabilitado cuando Inventario está apagado',
      (tester) async {
        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '66666666-6666-4666-8666-666666666666',
                'business_id': bizA,
                'name': 'Empleado Alfa',
                'email': 'emp@alfa.local',
                'role': 'EMPLOYEE',
                'is_active': true,
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/v1/businesses/$bizA/modules') {
            return http.Response(
              jsonEncode([
                {'key': 'inventory', 'enabled': false},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpLoggedInApp(tester, client: client);

        expect(find.byKey(const Key('inventory_disabled_banner')), findsOneWidget);
        expect(find.text('Módulo Inventario deshabilitado'), findsOneWidget);
      },
    );

    testWidgets(
      'empresa desactivada provoca 401 y regresa al usuario a LoginScreen',
      (tester) async {
        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '66666666-6666-4666-8666-666666666666',
                'business_id': bizA,
                'name': 'Empleado Alfa',
                'email': 'emp@alfa.local',
                'role': 'EMPLOYEE',
                'is_active': true,
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/v1/businesses/$bizA/modules') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'UNAUTHENTICATED',
                  'message': 'La empresa fue desactivada.',
                },
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpLoggedInApp(tester, client: client);

        expect(find.text('Iniciar sesión'), findsOneWidget);
        expect(find.text('La empresa fue desactivada.'), findsOneWidget);
      },
    );
  });
}
