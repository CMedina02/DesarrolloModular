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

/// Stateful in-memory OpenAPI 3.1.0 fake server supporting 2 isolated businesses
/// for F09 end-to-end acceptance testing.
class _StatefulFakeBackend {
  static const bizA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  static const bizB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  final Map<String, bool> inventoryEnabled = {
    bizA: true,
    bizB: true,
  };

  final Map<String, List<Map<String, dynamic>>> categoriesByBiz = {
    bizA: [],
    bizB: [],
  };

  final Map<String, List<Map<String, dynamic>>> productsByBiz = {
    bizA: [],
    bizB: [],
  };

  final Map<String, List<Map<String, dynamic>>> movementsByBiz = {
    bizA: [],
    bizB: [],
  };

  int _idSeq = 1;

  String _nextUuid() {
    final suffix = (_idSeq++).toString().padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }

  Map<String, dynamic>? _userForToken(String? authHeader) {
    switch (authHeader) {
      case 'Bearer tok-admin-a':
        return {
          'id': '11111111-1111-4111-8111-111111111111',
          'business_id': bizA,
          'name': 'Admin Alfa',
          'email': 'admin@alfa.local',
          'role': 'ADMIN',
          'is_active': true,
          'created_at': '2026-11-20T18:00:00Z',
          'updated_at': '2026-11-20T18:00:00Z',
        };
      case 'Bearer tok-emp-a':
        return {
          'id': '22222222-2222-4222-8222-222222222222',
          'business_id': bizA,
          'name': 'Empleado Alfa',
          'email': 'emp@alfa.local',
          'role': 'EMPLOYEE',
          'is_active': true,
          'created_at': '2026-11-20T18:00:00Z',
          'updated_at': '2026-11-20T18:00:00Z',
        };
      case 'Bearer tok-admin-b':
        return {
          'id': '33333333-3333-4333-8333-333333333333',
          'business_id': bizB,
          'name': 'Admin Beta',
          'email': 'admin@beta.local',
          'role': 'ADMIN',
          'is_active': true,
          'created_at': '2026-11-20T18:00:00Z',
          'updated_at': '2026-11-20T18:00:00Z',
        };
      default:
        return null;
    }
  }

  http.Response _json(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  MockClient toClient() {
    return MockClient((request) async {
      final path = request.url.path;

      if (path == '/health') {
        return _json({'status': 'ok'});
      }

      if (path == '/api/v1/auth/login' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final email = body['email'] as String;
        final password = body['password'] as String;
        if (password != 'PasswordSeguro12345!') {
          return _json({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Credenciales o sesión no válidas.',
            },
          }, 401);
        }
        final token = switch (email) {
          'admin@alfa.local' => 'tok-admin-a',
          'emp@alfa.local' => 'tok-emp-a',
          'admin@beta.local' => 'tok-admin-b',
          _ => null,
        };
        if (token == null) {
          return _json({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Credenciales o sesión no válidas.',
            },
          }, 401);
        }
        return _json({
          'access_token': token,
          'token_type': 'Bearer',
          'expires_in': 900,
          'user': _userForToken('Bearer $token'),
        });
      }

      final user = _userForToken(request.headers['Authorization']);
      if (user == null) {
        return _json({
          'error': {
            'code': 'UNAUTHENTICATED',
            'message': 'Sesión no válida.',
          },
        }, 401);
      }

      if (path == '/api/v1/auth/me') {
        return _json(user);
      }

      final bizId = user['business_id'] as String;

      if (path == '/api/v1/businesses/$bizId/modules') {
        return _json([
          {'key': 'inventory', 'enabled': inventoryEnabled[bizId] ?? false},
        ]);
      }

      if (!(inventoryEnabled[bizId] ?? false)) {
        return _json({
          'error': {
            'code': 'MODULE_DISABLED',
            'message': 'El módulo de Inventario está deshabilitado.',
          },
        }, 403);
      }

      if (path == '/api/v1/businesses/$bizId/inventory/categories') {
        if (request.method == 'GET') {
          return _json({
            'items': categoriesByBiz[bizId],
            'limit': 25,
            'offset': 0,
          });
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final created = {
            'id': _nextUuid(),
            'business_id': bizId,
            'name': body['name'],
            'created_at': '2026-11-24T10:00:00Z',
            'updated_at': '2026-11-24T10:00:00Z',
          };
          categoriesByBiz[bizId]!.add(created);
          return _json(created, 201);
        }
      }

      if (path == '/api/v1/businesses/$bizId/inventory/products') {
        if (request.method == 'GET') {
          final isActiveParam = request.url.queryParameters['is_active'];
          final items = productsByBiz[bizId]!.where((p) {
            if (isActiveParam == 'true') return p['is_active'] == true;
            if (isActiveParam == 'false') return p['is_active'] == false;
            return true;
          }).toList();
          return _json({'items': items, 'limit': 25, 'offset': 0});
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final created = {
            'id': _nextUuid(),
            'business_id': bizId,
            'category_id': body['category_id'],
            'sku': body['sku'],
            'name': body['name'],
            'unit': body['unit'],
            'cost_price': body['cost_price'] ?? '0.00',
            'sale_price': body['sale_price'] ?? '0.00',
            'min_stock': body['min_stock'] ?? '0.000',
            'is_active': body['is_active'] ?? true,
            'stock_quantity': '0.000',
            'created_at': '2026-11-24T10:05:00Z',
            'updated_at': '2026-11-24T10:05:00Z',
          };
          productsByBiz[bizId]!.add(created);
          return _json(created, 201);
        }
      }

      if (path.startsWith('/api/v1/businesses/$bizId/inventory/products/') &&
          request.method == 'GET') {
        final productId = path.split('/').last;
        final product =
            productsByBiz[bizId]!.firstWhere((p) => p['id'] == productId);
        return _json(product);
      }

      if (path == '/api/v1/businesses/$bizId/inventory/movements') {
        if (request.method == 'GET') {
          if (user['role'] != 'ADMIN') {
            return _json({
              'error': {
                'code': 'FORBIDDEN',
                'message': 'Solo ADMIN puede consultar el historial.',
              },
            }, 403);
          }
          return _json({
            'items': movementsByBiz[bizId]!.reversed.toList(),
            'limit': 25,
            'offset': 0,
          });
        }

        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final type = body['movement_type'] as String;
          final product = productsByBiz[bizId]!
              .firstWhere((p) => p['id'] == body['product_id']);
          final before = double.parse(product['stock_quantity'] as String);
          late double after;
          late double delta;

          if (type == 'IN') {
            final qty = double.parse(body['quantity'] as String);
            delta = qty;
            after = before + qty;
          } else if (type == 'OUT') {
            final qty = double.parse(body['quantity'] as String);
            if (qty > before) {
              return _json({
                'error': {
                  'code': 'INSUFFICIENT_STOCK',
                  'message': 'No hay existencias suficientes.',
                },
              }, 409);
            }
            delta = -qty;
            after = before - qty;
          } else {
            final counted = double.parse(body['counted_quantity'] as String);
            delta = counted - before;
            after = counted;
          }

          product['stock_quantity'] = after.toStringAsFixed(3);
          final movement = {
            'id': _nextUuid(),
            'business_id': bizId,
            'product_id': product['id'],
            'user_id': user['id'],
            'movement_type': type,
            'quantity_delta': delta.toStringAsFixed(3),
            'stock_before': before.toStringAsFixed(3),
            'stock_after': after.toStringAsFixed(3),
            'reason': body['reason'],
            'created_at': '2026-11-24T10:10:00Z',
          };
          movementsByBiz[bizId]!.add(movement);
          return _json(movement, 201);
        }
      }

      return _json({
        'error': {'code': 'NOT_FOUND', 'message': 'No encontrado.'},
      }, 404);
    });
  }
}

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  testWidgets(
    'F09 E2E: flujo ADMIN, EMPLOYEE, aislamiento multiempresa y recuperación',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final backend = _StatefulFakeBackend();
      final storage = InMemoryTokenStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(testConfig),
            httpClientProvider.overrideWithValue(backend.toClient()),
            tokenStorageProvider.overrideWithValue(storage),
          ],
          child: const InventarioComercialApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 5. Recuperación: credenciales inválidas conservan formulario y luego login válido
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'admin@alfa.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'clave-invalida',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'PasswordSeguro12345!',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      // 2. Flujo ADMIN: crear categoría -> crear producto (0.000) -> IN -> OUT -> ADJUSTMENT -> Historial
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create_category_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_name_field')),
        'Bebidas',
      );
      await tester.tap(find.byKey(const Key('category_save_button')));
      await tester.pumpAndSettle();
      expect(find.text('Bebidas'), findsOneWidget);

      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create_product_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('product_sku_field')),
        'AGU-600',
      );
      await tester.enterText(
        find.byKey(const Key('product_name_field')),
        'Agua 600ml',
      );
      await tester.enterText(
        find.byKey(const Key('product_sale_price_field')),
        '19.90',
      );
      await tester.tap(find.byKey(const Key('product_save_button')));
      await tester.pumpAndSettle();
      expect(find.text('Agua 600ml'), findsOneWidget);
      expect(find.textContaining('Stock: 0.000 PZA'), findsOneWidget);

      // Movimientos: IN (+10), OUT (-3), ADJUSTMENT (5)
      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('movement_quantity_field')),
        '10',
      );
      await tester.tap(find.byKey(const Key('movement_submit_button')));
      await tester.pumpAndSettle();
      expect(find.text('10.000 PZA'), findsOneWidget);

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

      // Stock insuficiente (409) conserva 7.000
      await tester.enterText(
        find.byKey(const Key('movement_quantity_field')),
        '99',
      );
      await tester.enterText(
        find.byKey(const Key('movement_reason_field')),
        'Exceso',
      );
      await tester.tap(find.byKey(const Key('movement_submit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movement_error_banner')), findsOneWidget);
      expect(find.text('7.000 PZA'), findsOneWidget);

      // Ajuste a 5
      await tester.tap(find.text('Ajuste'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('movement_quantity_field')),
        '5',
      );
      await tester.enterText(
        find.byKey(const Key('movement_reason_field')),
        'Conteo físico',
      );
      await tester.tap(find.byKey(const Key('movement_submit_button')));
      await tester.pumpAndSettle();
      expect(find.text('5.000 PZA'), findsOneWidget);

      // Historial refleja los 3 movimientos
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ADJUSTMENT · Agua 600ml'), findsOneWidget);
      expect(find.textContaining('OUT · Agua 600ml'), findsOneWidget);
      expect(find.textContaining('IN · Agua 600ml'), findsOneWidget);

      // 3. Flujo EMPLOYEE: cerrar sesión -> entrar como EMPLOYEE Alfa
      await tester.tap(find.byKey(const Key('shell_logout_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'emp@alfa.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'PasswordSeguro12345!',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Operación de inventario'), findsOneWidget);
      expect(find.text('Agua 600ml'), findsOneWidget);
      expect(find.byKey(const Key('create_product_fab')), findsNothing);
      expect(find.text('Historial'), findsNothing);
      expect(find.text('Empleados'), findsNothing);

      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Ajuste'), findsNothing);
      await tester.tap(find.text('Salida'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('movement_quantity_field')),
        '1',
      );
      await tester.enterText(
        find.byKey(const Key('movement_reason_field')),
        'Venta empleado',
      );
      await tester.tap(find.byKey(const Key('movement_submit_button')));
      await tester.pumpAndSettle();
      expect(find.text('4.000 PZA'), findsOneWidget);

      // 4. Aislamiento: cerrar sesión -> entrar como ADMIN Beta (otra empresa)
      await tester.tap(find.byKey(const Key('shell_logout_button')));
      await tester.pumpAndSettle();

      // Deshabilitar Inventario en Beta para probar recuperación del módulo
      backend.inventoryEnabled[_StatefulFakeBackend.bizB] = false;

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'admin@beta.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'PasswordSeguro12345!',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventory_disabled_banner')), findsOneWidget);

      // Habilitar Inventario en Beta y actualizar estado -> catálogo vacío y aislado de Alfa
      backend.inventoryEnabled[_StatefulFakeBackend.bizB] = true;
      await tester.tap(find.text('Actualizar estado'));
      await tester.pumpAndSettle();

      expect(find.text('Agua 600ml'), findsNothing);
      expect(
        find.text('No hay productos que coincidan con los filtros.'),
        findsOneWidget,
      );
    },
  );
}
