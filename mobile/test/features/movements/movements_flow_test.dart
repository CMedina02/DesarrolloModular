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
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const cat1Id = '11111111-1111-4111-8111-111111111111';
  const prod1Id = '77777777-7777-4777-8777-777777777777';

  Map<String, dynamic> productJson(String stock, {String unit = 'PZA'}) => {
        'id': prod1Id,
        'business_id': bizA,
        'category_id': cat1Id,
        'sku': 'BEB-001',
        'name': 'Agua 600ml',
        'unit': unit,
        'cost_price': '10.00',
        'sale_price': '19.90',
        'min_stock': '5.000',
        'is_active': true,
        'stock_quantity': stock,
        'created_at': '2026-11-20T18:00:00Z',
        'updated_at': '2026-11-20T18:00:00Z',
      };

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required http.Client client,
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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

  group('F07: Entradas, salidas y ajustes', () {
    testWidgets(
      'ADMIN registra entrada, salida y ajuste actualizando el saldo confirmado',
      (tester) async {
        var currentStock = '0.000';

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
              jsonEncode({'items': [], 'limit': 100, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizA/inventory/products') {
            return http.Response(
              jsonEncode({
                'items': [productJson(currentStock)],
                'limit': 100,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/movements' &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final type = body['movement_type'] as String;
            final before = currentStock;
            late String delta;
            if (type == 'IN') {
              currentStock = '10.000';
              delta = '10.000';
            } else if (type == 'OUT') {
              currentStock = '7.000';
              delta = '-3.000';
            } else {
              expect(body['counted_quantity'], '5');
              currentStock = '5.000';
              delta = '-2.000';
            }
            return http.Response(
              jsonEncode({
                'id': '66666666-6666-4666-8666-666666666666',
                'business_id': bizA,
                'product_id': prod1Id,
                'user_id': '99999999-9999-4999-8999-999999999999',
                'movement_type': type,
                'quantity_delta': delta,
                'stock_before': before,
                'stock_after': currentStock,
                'reason': body['reason'],
                'created_at': '2026-11-21T20:00:00Z',
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Movimientos'));
        await tester.pumpAndSettle();

        expect(find.text('0.000 PZA'), findsOneWidget);

        // 1. Entrada (IN) sin motivo opcional
        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '10',
        );
        await tester.tap(find.byKey(const Key('movement_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('10.000 PZA'), findsOneWidget);
        expect(find.byKey(const Key('movement_success_card')), findsOneWidget);

        // 2. Salida (OUT) con motivo
        await tester.tap(find.text('Salida'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '3',
        );
        await tester.enterText(
          find.byKey(const Key('movement_reason_field')),
          'Venta mostrador',
        );
        await tester.tap(find.byKey(const Key('movement_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('7.000 PZA'), findsOneWidget);

        // 3. Ajuste (ADJUSTMENT) solo ADMIN
        await tester.tap(find.text('Ajuste'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '5',
        );
        await tester.enterText(
          find.byKey(const Key('movement_reason_field')),
          'Conteo físico semanal',
        );
        await tester.tap(find.byKey(const Key('movement_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('5.000 PZA'), findsOneWidget);
      },
    );

    testWidgets(
      'EMPLOYEE no ve Ajuste, valida motivo/fracción en PZA y conserva saldo ante 409',
      (tester) async {
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
            return http.Response(
              jsonEncode({
                'items': [productJson('7.000')],
                'limit': 100,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/movements' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'INSUFFICIENT_STOCK',
                  'message': 'Stock insuficiente para la salida.',
                },
              }),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Movimientos'));
        await tester.pumpAndSettle();

        expect(find.text('Ajuste'), findsNothing);
        expect(find.text('7.000 PZA'), findsOneWidget);

        // Select Salida
        await tester.tap(find.text('Salida'));
        await tester.pumpAndSettle();

        // Fractional quantity in PZA + missing reason
        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '1.5',
        );
        await tester.tap(find.byKey(const Key('movement_submit_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('La unidad PZA solo admite cantidades enteras.'),
          findsOneWidget,
        );
        expect(
          find.text('El motivo es obligatorio para salida.'),
          findsOneWidget,
        );

        // Exceeds balance -> 409 preserves last confirmed stock "7.000 PZA"
        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '20',
        );
        await tester.enterText(
          find.byKey(const Key('movement_reason_field')),
          'Pedido grande',
        );
        await tester.tap(find.byKey(const Key('movement_submit_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('movement_error_banner')), findsOneWidget);
        expect(find.text('7.000 PZA'), findsOneWidget);
      },
    );

    testWidgets(
      'doble toque en respuesta lenta envía 1 solicitud y timeout ofrece verificar saldo',
      (tester) async {
        var postCalls = 0;
        final slowPost = Completer<http.Response>();

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
              jsonEncode({'items': [], 'limit': 100, 'offset': 0}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizA/inventory/products') {
            return http.Response(
              jsonEncode({
                'items': [productJson('4.000')],
                'limit': 100,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/v1/businesses/$bizA/inventory/products/$prod1Id') {
            return http.Response(
              jsonEncode(productJson('9.000')),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
                  '/api/v1/businesses/$bizA/inventory/movements' &&
              request.method == 'POST') {
            postCalls++;
            return slowPost.future;
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Movimientos'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('movement_quantity_field')),
          '5',
        );

        final btn = find.byKey(const Key('movement_submit_button'));
        await tester.tap(btn);
        await tester.pump();
        await tester.tap(btn, warnIfMissed: false);
        await tester.pump();

        expect(postCalls, 1);

        // Simulate post-send timeout -> uncertain confirmation banner
        slowPost.completeError(TimeoutException('Lost connection'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('movement_uncertain_banner')),
          findsOneWidget,
        );
        expect(find.text('4.000 PZA'), findsOneWidget);

        // Verify current balance from server -> updates to "9.000 PZA"
        await tapVisible(
          tester,
          find.byKey(const Key('uncertain_verify_stock_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('9.000 PZA'), findsOneWidget);
      },
    );
  });
}
