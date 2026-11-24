import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_comercial/core/models/models.dart';

void main() {
  group('OpenAPI models deserialization and serialization', () {
    test('deserializa Product conservando decimales exactos "19.90" y "0.125"', () {
      final json = <String, dynamic>{
        'id': '11111111-1111-4111-8111-111111111111',
        'business_id': '22222222-2222-4222-8222-222222222222',
        'category_id': '33333333-3333-4333-8333-333333333333',
        'sku': 'CAFE-001',
        'name': 'Café molido artesanal',
        'unit': 'KG',
        'cost_price': '12.50',
        'sale_price': '19.90',
        'min_stock': '0.125',
        'is_active': true,
        'stock_quantity': '0.000',
        'created_at': '2026-11-20T18:00:00Z',
        'updated_at': '2026-11-20T18:00:00Z',
      };

      final product = Product.fromJson(json);

      expect(product.id, '11111111-1111-4111-8111-111111111111');
      expect(product.unit, ProductUnit.kg);
      expect(product.unit.requiresIntegerQuantity, isFalse);
      expect(product.costPrice, '12.50');
      expect(product.salePrice, '19.90');
      expect(product.minStock, '0.125');
      expect(product.stockQuantity, '0.000');
      expect(product.isActive, isTrue);
    });

    test('deserializa PaginatedList con items, limit y offset', () {
      final json = <String, dynamic>{
        'items': [
          {
            'id': '33333333-3333-4333-8333-333333333333',
            'business_id': '22222222-2222-4222-8222-222222222222',
            'name': 'Bebidas',
            'created_at': '2026-11-20T18:00:00Z',
            'updated_at': '2026-11-20T18:00:00Z',
          },
        ],
        'limit': 25,
        'offset': 0,
      };

      final list = PaginatedList.fromJson(json, Category.fromJson);

      expect(list.items, hasLength(1));
      expect(list.items.first.name, 'Bebidas');
      expect(list.limit, 25);
      expect(list.offset, 0);
      expect(list.hasMore, isFalse);
    });

    test('deserializa ApiErrorBody con error.code y error.message', () {
      final json = <String, dynamic>{
        'error': {
          'code': 'CONFLICT',
          'message': 'El SKU ya existe en esta empresa.',
        },
      };

      final error = ApiErrorBody.fromJson(json);

      expect(error.code, 'CONFLICT');
      expect(error.message, 'El SKU ya existe en esta empresa.');
    });

    test('serializa solicitudes de movimiento respetando decimales como cadenas', () {
      const entry = StockEntryRequest(
        productId: '11111111-1111-4111-8111-111111111111',
        quantity: '2.500',
      );
      const exit = StockExitRequest(
        productId: '11111111-1111-4111-8111-111111111111',
        quantity: '1.250',
        reason: 'Venta mostrador',
      );
      const adjustment = StockAdjustmentRequest(
        productId: '11111111-1111-4111-8111-111111111111',
        countedQuantity: '10.000',
        reason: 'Conteo físico semanal',
      );

      expect(entry.toJson(), {
        'movement_type': 'IN',
        'product_id': '11111111-1111-4111-8111-111111111111',
        'quantity': '2.500',
      });
      expect(exit.toJson()['movement_type'], 'OUT');
      expect(exit.toJson()['reason'], 'Venta mostrador');
      expect(adjustment.toJson()['movement_type'], 'ADJUSTMENT');
      expect(adjustment.toJson()['counted_quantity'], '10.000');
    });

    test('oculta contraseñas y tokens en toString()', () {
      const loginReq = LoginRequest(
        email: 'admin@demo.local',
        password: 'super-secret-password-123',
      );
      final loginRes = LoginResponse.fromJson({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.secret.sig',
        'token_type': 'Bearer',
        'expires_in': 900,
        'user': {
          'id': '44444444-4444-4444-8444-444444444444',
          'business_id': null,
          'name': 'Platform Admin',
          'email': 'root@demo.local',
          'role': 'PLATFORM_ADMIN',
          'is_active': true,
          'created_at': '2026-11-20T18:00:00Z',
          'updated_at': '2026-11-20T18:00:00Z',
        },
      });

      expect(loginReq.toString(), isNot(contains('super-secret-password-123')));
      expect(loginRes.toString(), isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(loginRes.user.businessId, isNull);
      expect(loginRes.user.role, UserRole.platformAdmin);
    });

    test('identifica unidades discretas que requieren enteros', () {
      expect(ProductUnit.pza.requiresIntegerQuantity, isTrue);
      expect(ProductUnit.caja.requiresIntegerQuantity, isTrue);
      expect(ProductUnit.kg.requiresIntegerQuantity, isFalse);
      expect(ProductUnit.m.requiresIntegerQuantity, isFalse);
      expect(ProductUnit.l.requiresIntegerQuantity, isFalse);
    });
  });
}
