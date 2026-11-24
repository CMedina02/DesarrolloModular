import 'package:inventario_comercial/core/models/category.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Repository for `/businesses/{business_id}/inventory/categories`.
class CategoriesRepository {
  CategoriesRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaginatedList<Category>> listCategories(
    String businessId, {
    int limit = 25,
    int offset = 0,
  }) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/inventory/categories',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return PaginatedList.fromJson(json, Category.fromJson);
  }

  Future<Category> getCategory(String businessId, String categoryId) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/inventory/categories/$categoryId',
    );
    return Category.fromJson(json);
  }

  Future<Category> createCategory(String businessId, String name) async {
    final json = await _apiClient.postJson(
      '/businesses/$businessId/inventory/categories',
      body: CategoryUpsertRequest(name: name.trim()).toJson(),
    );
    return Category.fromJson(json);
  }

  Future<Category> updateCategory(
    String businessId,
    String categoryId,
    String name,
  ) async {
    final json = await _apiClient.patchJson(
      '/businesses/$businessId/inventory/categories/$categoryId',
      body: CategoryUpsertRequest(name: name.trim()).toJson(),
    );
    return Category.fromJson(json);
  }

  /// Expects `204 No Content`. Throws `409` if category has associated products.
  Future<void> deleteCategory(String businessId, String categoryId) async {
    await _apiClient.deleteNoContent(
      '/businesses/$businessId/inventory/categories/$categoryId',
    );
  }
}
