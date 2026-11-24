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
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';
import 'package:inventario_comercial/features/movements/application/movements_providers.dart';

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const prod1Id = '77777777-7777-4777-8777-777777777777';
  const mov1Id = '66666666-6666-4666-8666-666666666666';

  Future<void> pumpApp(
    WidgetTester tester, {
    required http.Client client,
  }) async {
    tester.view.physicalSize = const Size(1100, 900);
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

  group('F08: Historial de movimientos', () {
    test(
      'envía from (inclusivo) y to (exclusivo) en RFC 3339 UTC y distingue 403 para EMPLOYEE',
      () async {
        late Uri capturedUri;

        final client = MockClient((request) async {
          capturedUri = request.url;
          if (request.headers['Authorization'] == 'Bearer emp-token') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'FORBIDDEN',
                  'message': 'Solo ADMIN puede consultar el historial.',
                },
              }),
              403,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
            200,
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

        await container.read(movementsRepositoryProvider).listMovements(
              bizA,
              productId: prod1Id,
              movementType: MovementType.exit,
              from: DateTime.utc(2026, 11, 20, 0, 0, 0),
              to: DateTime.utc(2026, 11, 22, 0, 0, 0),
              limit: 25,
              offset: 0,
            );

        expect(
          capturedUri.path,
          '/api/v1/businesses/$bizA/inventory/movements',
        );
        expect(capturedUri.queryParameters['product_id'], prod1Id);
        expect(capturedUri.queryParameters['movement_type'], 'OUT');
        expect(
          capturedUri.queryParameters['from'],
          '2026-11-20T00:00:00.000Z',
        );
        expect(
          capturedUri.queryParameters['to'],
          '2026-11-22T00:00:00.000Z',
        );

        // Direct API call with EMPLOYEE token returns 403
        container.read(authTokenProvider.notifier).setToken('emp-token');
        expect(
          () => container.read(movementsRepositoryProvider).listMovements(bizA),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.isForbidden, 'isForbidden', isTrue),
          ),
        );
      },
    );

    testWidgets(
      'ADMIN consulta historial, abre detalle, aplica/limpia filtros y maneja error/vacío',
      (tester) async {
        final seenQueries = <Map<String, String>>[];
        var failNextHistory = false;

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
                'items': [
                  {
                    'id': prod1Id,
                    'business_id': bizA,
                    'category_id': '11111111-1111-4111-8111-111111111111',
                    'sku': 'BEB-001',
                    'name': 'Agua 600ml',
                    'unit': 'PZA',
                    'cost_price': '10.00',
                    'sale_price': '19.90',
                    'min_stock': '5.000',
                    'is_active': true,
                    'stock_quantity': '7.000',
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
              '/api/v1/businesses/$bizA/inventory/movements') {
            seenQueries.add(request.url.queryParameters);
            if (failNextHistory) {
              failNextHistory = false;
              return http.Response(
                jsonEncode({
                  'error': {
                    'code': 'INTERNAL_ERROR',
                    'message': 'Error temporal del historial.',
                  },
                }),
                500,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.queryParameters['movement_type'] == 'ADJUSTMENT') {
              return http.Response(
                jsonEncode({'items': [], 'limit': 25, 'offset': 0}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': mov1Id,
                    'business_id': bizA,
                    'product_id': prod1Id,
                    'user_id': '99999999-9999-4999-8999-999999999999',
                    'movement_type': 'OUT',
                    'quantity_delta': '-3.000',
                    'stock_before': '10.000',
                    'stock_after': '7.000',
                    'reason': 'Venta mostrador',
                    'created_at': '2026-11-21T20:00:00Z',
                  },
                ],
                'limit': 25,
                'offset': 0,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not found', 404);
        });

        await pumpApp(tester, client: client);
        await tester.tap(find.text('Historial'));
        await tester.pumpAndSettle();

        expect(find.text('OUT · Agua 600ml (BEB-001)'), findsOneWidget);
        expect(find.textContaining('Venta mostrador'), findsOneWidget);

        // Open detail dialog
        await tester.tap(find.text('OUT · Agua 600ml (BEB-001)'));
        await tester.pumpAndSettle();
        expect(find.text('Detalle de movimiento'), findsOneWidget);
        expect(find.text('-3.000'), findsOneWidget);
        expect(find.text('7.000'), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        // Filter by ADJUSTMENT -> empty state + clear filters button appears
        await tester.tap(find.byKey(const Key('history_type_filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ADJUSTMENT (Ajuste)').last);
        await tester.pumpAndSettle();

        expect(seenQueries.last['movement_type'], 'ADJUSTMENT');
        expect(seenQueries.last['offset'], '0');
        expect(
          find.text(
            'No hay movimientos registrados para los filtros seleccionados.',
          ),
          findsOneWidget,
        );

        // Trigger error on next clear, then retry
        failNextHistory = true;
        await tester.tap(find.byKey(const Key('history_clear_filters_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('history_retry_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('history_retry_button')));
        await tester.pumpAndSettle();

        expect(find.text('OUT · Agua 600ml (BEB-001)'), findsOneWidget);
      },
    );
  });
}
