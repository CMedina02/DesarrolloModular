import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Repository for `/businesses/{business_id}/inventory/products`.
class ProductsRepository {
  ProductsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaginatedList<Product>> listProducts(
    String businessId, {
    int limit = 25,
    int offset = 0,
    String? categoryId,
    bool? isActive,
    bool lowStock = false,
  }) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/inventory/products',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        'is_active': ?isActive,
        if (lowStock) 'low_stock': true,
      },
    );
    return PaginatedList.fromJson(json, Product.fromJson);
  }

  Future<Product> getProduct(String businessId, String productId) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/inventory/products/$productId',
    );
    return Product.fromJson(json);
  }

  Future<Product> createProduct(
    String businessId,
    ProductCreateRequest request,
  ) async {
    final json = await _apiClient.postJson(
      '/businesses/$businessId/inventory/products',
      body: request.toJson(),
    );
    return Product.fromJson(json);
  }

  Future<Product> updateProduct(
    String businessId,
    String productId,
    ProductUpdateRequest request,
  ) async {
    final json = await _apiClient.patchJson(
      '/businesses/$businessId/inventory/products/$productId',
      body: request.toJson(),
    );
    return Product.fromJson(json);
  }

  Future<Product> deactivateProduct(String businessId, String productId) {
    return updateProduct(
      businessId,
      productId,
      const ProductUpdateRequest(isActive: false),
    );
  }
}
