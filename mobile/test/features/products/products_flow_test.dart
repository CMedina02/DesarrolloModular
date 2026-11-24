import 'dart:async';
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
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';
import 'package:inventario_comercial/features/products/application/product_validators.dart';

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const cat1Id = '11111111-1111-4111-8111-111111111111';
  const prod1Id = '77777777-7777-4777-8777-777777777777';

  Future<void> pumpApp(
    WidgetTester tester, {
    required http.Client client,
    bool settle = true,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  group('ProductValidators', () {
    test('valida precios con hasta 2 decimales y rechaza negativos o 3 decimales', () {
      expect(ProductValidators.validatePrice('19.90'), isNull);
      expect(ProductValidators.validatePrice('0'), isNull);
      expect(ProductValidators.validatePrice('19.995'), isNotNull);
      expect(ProductValidators.validatePrice('-5.00'), isNotNull);
    });

    test('exige enteros en PZA/CAJA y permite 3 decimales en KG/M/L', () {
      expect(
        ProductValidators.validateQuantity('5', unit: ProductUnit.pza),
        isNull,
      );
      expect(
        ProductValidators.validateQuantity('1.5', unit: ProductUnit.pza),
        isNotNull,
      );
      expect(
        ProductValidators.validateQuantity('0.125', unit: ProductUnit.kg),
        isNull,
      );
      expect(
        ProductValidators.validateQuantity('0.1255', unit: ProductUnit.kg),
        isNotNull,
      );
    });
  });

  group('F06: Catálogo de productos', () {
    testWidgets(
      'ADMIN crea producto con "19.90", verifica detalle con stock "0.000", edita y desactiva',
      (tester) async {
        final products = <Map<String, dynamic>>[];

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
              '/api/v1/businesses/$bizA/inventory/categories') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': cat1Id,
                    'business_id': bizA,
                    'name': 'Bebidas',
                    'created_at': '2026-11-20T18:00:00Z',
                    'updated_at': '2026-11-20T18:00:00Z',
                  },
                ],
                'limit': 100,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': products, 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final created = {
              'id': prod1Id,
              'business_id': bizA,
              'category_id': body['category_id'],
              'sku': body['sku'],
              'name': body['name'],
              'unit': body['unit'],
              'cost_price': body['cost_price'] ?? '0.00',
              'sale_price': body['sale_price'] ?? '0.00',
              'min_stock': body['min_stock'] ?? '0.000',
              'is_active': body['is_active'] ?? true,
              'stock_quantity': '0.000',
              'created_at': '2026-11-20T19:00:00Z',
              'updated_at': '2026-11-20T19:00:00Z',
            };
            products.add(created);
            return http.Response(
              jsonEncode(created),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products/$prod1Id' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode(products.first),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products/$prod1Id' &&
              request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            products.first.addAll(body);
            return http.Response(
              jsonEncode(products.first),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);

        // Create product with sale_price "19.90"
        await tester.tap(find.byKey(const Key('create_product_fab')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('product_readonly_stock')), findsOneWidget);
        expect(find.text('0.000'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('product_sku_field')),
          'BEB-001',
        );
        await tester.enterText(
          find.byKey(const Key('product_name_field')),
          'Agua Mineral 600ml',
        );
        await tester.enterText(
          find.byKey(const Key('product_sale_price_field')),
          '19.90',
        );
        await tester.enterText(
          find.byKey(const Key('product_min_stock_field')),
          '5',
        );
        await tester.tap(find.byKey(const Key('product_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Agua Mineral 600ml'), findsOneWidget);

        // Open detail and verify "19.90" and "0.000"
        await tester.tap(find.text('Agua Mineral 600ml'));
        await tester.pumpAndSettle();

        expect(find.text('Detalle de producto'), findsOneWidget);
        expect(find.text('19.90'), findsOneWidget);
        expect(find.text('0.000'), findsOneWidget);

        // Edit from detail -> change price to "21.50"
        await tester.tap(find.byKey(const Key('detail_edit_product_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('product_sale_price_field')),
          '21.50',
        );
        await tester.tap(find.byKey(const Key('product_save_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('21.50'), findsOneWidget);

        // Deactivate product
        await tester
            .tap(find.byKey(const Key('deactivate_product_$prod1Id')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Inactivo'), findsOneWidget);
      },
    );

    testWidgets(
      'rechaza mínimo fraccionario en PZA y conserva formulario ante SKU duplicado 409',
      (tester) async {
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
              '/api/v1/businesses/$bizA/inventory/categories') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': cat1Id,
                    'business_id': bizA,
                    'name': 'Bebidas',
                    'created_at': '2026-11-20T18:00:00Z',
                    'updated_at': '2026-11-20T18:00:00Z',
                  },
                ],
                'limit': 100,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/products' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'CONFLICT',
                  'message': 'El SKU ya existe en esta empresa.',
                },
              }),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);

        await tester.tap(find.byKey(const Key('create_product_fab')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('product_sku_field')),
          'DUP-001',
        );
        await tester.enterText(
          find.byKey(const Key('product_name_field')),
          'Refresco Cola',
        );
        await tester.enterText(
          find.byKey(const Key('product_min_stock_field')),
          '1.5',
        );
        await tester.tap(find.byKey(const Key('product_save_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('La unidad PZA solo admite cantidades enteras.'),
          findsOneWidget,
        );

        // Fix min_stock to integer -> server returns 409 duplicate SKU
        await tester.enterText(
          find.byKey(const Key('product_min_stock_field')),
          '2',
        );
        await tester.tap(find.byKey(const Key('product_save_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('product_form_error')), findsOneWidget);
        expect(find.text('El SKU ya existe en esta empresa.'), findsOneWidget);
        // Form retains user inputs
        expect(find.text('DUP-001'), findsOneWidget);
        expect(find.text('Refresco Cola'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra esqueleto de carga, filtros (low_stock) y solo lectura para EMPLOYEE',
      (tester) async {
        final productsCompleter = Completer<http.Response>();
        final seenQueries = <Map<String, String>>[];

        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/me') {
            return http.Response(
              jsonEncode({
                'id': '88888888-8888-4888-8888-888888888888',
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
                {'key': 'inventory', 'enabled': true},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizA/inventory/categories') {
            return http.Response(
              jsonEncode({'items': [], 'limit': 100, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizA/inventory/products') {
            seenQueries.add(request.url.queryParameters);
            if (!productsCompleter.isCompleted) {
              return productsCompleter.future;
            }
            return http.Response(
              jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client, settle: false);
        await tester.pump(const Duration(milliseconds: 50));

        // Loading skeleton visible while products are in flight
        expect(
          find.byKey(const Key('products_loading_skeleton')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('create_product_fab')), findsNothing);
        expect(find.byKey(const Key('products_status_filter')), findsNothing);

        // Complete initial load -> empty state
        productsCompleter.complete(
          http.Response(
            jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('No hay productos que coincidan con los filtros.'),
          findsOneWidget,
        );

        // Toggle low_stock filter -> triggers query with low_stock=true & is_active=true
        await tester.tap(find.byKey(const Key('products_low_stock_filter')));
        await tester.pumpAndSettle();

        expect(seenQueries.last['is_active'], 'true');
        expect(seenQueries.last['low_stock'], 'true');
      },
    );
  });
}
