import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_comercial/app/app.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const bizB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const cat1Id = '11111111-1111-4111-8111-111111111111';
  const cat2Id = '22222222-2222-4222-8222-222222222222';

  Future<void> pumpApp(
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

  group('F05: Categorías', () {
    testWidgets(
      'ADMIN crea, renombra y elimina una categoría libre (204)',
      (tester) async {
        final categories = <Map<String, dynamic>>[];

        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '99999999-9999-4999-8999-999999999999',
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

          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': categories, 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final created = {
              'id': cat1Id,
              'business_id': bizA,
              'name': body['name'],
              'created_at': '2026-11-20T19:00:00Z',
              'updated_at': '2026-11-20T19:00:00Z',
            };
            categories.add(created);
            return http.Response(
              jsonEncode(created),
              201,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories/$cat1Id' &&
              request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            categories[0]['name'] = body['name'];
            return http.Response(
              jsonEncode(categories[0]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories/$cat1Id' &&
              request.method == 'DELETE') {
            categories.removeWhere((c) => c['id'] == cat1Id);
            return http.Response('', 204);
          }

          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);

        await tester.tap(find.text('Categorías'));
        await tester.pumpAndSettle();

        expect(
          find.text('No hay categorías registradas todavía.'),
          findsOneWidget,
        );

        // Create
        await tester.tap(find.byKey(const Key('create_category_fab')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('category_name_field')),
          '  Bebidas  ',
        );
        await tester.tap(find.byKey(const Key('category_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Bebidas'), findsOneWidget);

        // Rename
        await tester.tap(find.byKey(const Key('edit_category_$cat1Id')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('category_name_field')),
          'Bebidas Frías',
        );
        await tester.tap(find.byKey(const Key('category_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Bebidas Frías'), findsOneWidget);

        // Delete (204)
        await tester.tap(find.byKey(const Key('delete_category_$cat1Id')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const Key('confirm_delete_category_button')));
        await tester.pumpAndSettle();

        expect(find.text('Bebidas Frías'), findsNothing);
        expect(
          find.text('No hay categorías registradas todavía.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'valida nombre vacío, duplicado 409 y conserva registro cuando falla DELETE 409',
      (tester) async {
        final categories = <Map<String, dynamic>>[
          {
            'id': cat1Id,
            'business_id': bizA,
            'name': 'Lácteos',
            'created_at': '2026-11-20T18:00:00Z',
            'updated_at': '2026-11-20T18:00:00Z',
          },
        ];

        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '99999999-9999-4999-8999-999999999999',
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
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': categories, 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'CONFLICT',
                  'message': 'Ya existe una categoría con ese nombre.',
                },
              }),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/categories/$cat1Id' &&
              request.method == 'DELETE') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'CONFLICT',
                  'message':
                      'No se puede eliminar una categoría con productos asociados.',
                },
              }),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Categorías'));
        await tester.pumpAndSettle();

        // Empty name validation
        await tester.tap(find.byKey(const Key('create_category_fab')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('category_name_field')),
          '   ',
        );
        await tester.tap(find.byKey(const Key('category_save_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Ingresa un nombre válido (1 a 100 caracteres).'),
          findsOneWidget,
        );

        // Case-insensitive duplicate (409)
        await tester.enterText(
          find.byKey(const Key('category_name_field')),
          'LÁCTEOS',
        );
        await tester.tap(find.byKey(const Key('category_save_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('category_form_error')), findsOneWidget);
        expect(find.text('LÁCTEOS'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        // Delete with associated products (409) keeps item in list
        await tester.tap(find.byKey(const Key('delete_category_$cat1Id')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const Key('confirm_delete_category_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('category_action_error')), findsOneWidget);
        expect(
          find.text(
            'No se puede eliminar una categoría con productos asociados.',
          ),
          findsOneWidget,
        );
        expect(find.text('Lácteos'), findsOneWidget);
      },
    );

    testWidgets(
      'EMPLOYEE consulta listado/detalle sin controles de escritura y aislado a su empresa',
      (tester) async {
        final requestedPaths = <String>[];

        final client = MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '88888888-8888-4888-8888-888888888888',
                'business_id': bizB,
                'name': 'Empleado Beta',
                'email': 'emp@beta.local',
                'role': 'EMPLOYEE',
                'is_active': true,
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/v1/businesses/$bizB/modules') {
            return http.Response(
              jsonEncode([
                {'key': 'inventory', 'enabled': true},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizB/inventory/categories') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': cat2Id,
                    'business_id': bizB,
                    'name': 'Ferretería Beta',
                    'created_at': '2026-11-20T18:00:00Z',
                    'updated_at': '2026-11-20T18:00:00Z',
                  },
                ],
                'limit': 25,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizB/inventory/categories/$cat2Id') {
            return http.Response(
              jsonEncode({
                'id': cat2Id,
                'business_id': bizB,
                'name': 'Ferretería Beta',
                'created_at': '2026-11-20T18:00:00Z',
                'updated_at': '2026-11-20T18:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Categorías'));
        await tester.pumpAndSettle();

        expect(find.text('Ferretería Beta'), findsOneWidget);
        expect(find.byKey(const Key('create_category_fab')), findsNothing);
        expect(find.byKey(const Key('edit_category_$cat2Id')), findsNothing);
        expect(find.byKey(const Key('delete_category_$cat2Id')), findsNothing);

        // Open detail
        await tester.tap(find.text('Ferretería Beta'));
        await tester.pumpAndSettle();

        expect(find.text('Detalle de categoría'), findsOneWidget);
        expect(find.text('Nombre: Ferretería Beta'), findsOneWidget);
        expect(
          requestedPaths.every((p) => !p.contains(bizA)),
          isTrue,
        );
      },
    );
  });
}
