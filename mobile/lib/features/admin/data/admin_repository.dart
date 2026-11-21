import 'package:inventario_comercial/core/models/business.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Repository for Core business, user, and module administration endpoints.
class AdminRepository {
  AdminRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaginatedList<Business>> listBusinesses({
    int limit = 25,
    int offset = 0,
  }) async {
    final json = await _apiClient.getJson(
      '/businesses',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return PaginatedList.fromJson(json, Business.fromJson);
  }

  Future<Business> getBusiness(String businessId) async {
    final json = await _apiClient.getJson('/businesses/$businessId');
    return Business.fromJson(json);
  }

  Future<Business> createBusiness(BusinessCreateRequest request) async {
    final json = await _apiClient.postJson(
      '/businesses',
      body: request.toJson(),
    );
    return Business.fromJson(json);
  }

  Future<Business> updateBusiness(
    String businessId,
    BusinessUpdateRequest request,
  ) async {
    final json = await _apiClient.patchJson(
      '/businesses/$businessId',
      body: request.toJson(),
    );
    return Business.fromJson(json);
  }

  Future<PaginatedList<User>> listUsers(
    String businessId, {
    int limit = 25,
    int offset = 0,
  }) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/users',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return PaginatedList.fromJson(json, User.fromJson);
  }

  Future<User> createUser(
    String businessId,
    UserCreateRequest request,
  ) async {
    final json = await _apiClient.postJson(
      '/businesses/$businessId/users',
      body: request.toJson(),
    );
    return User.fromJson(json);
  }

  Future<User> updateUser(
    String businessId,
    String userId,
    UserUpdateRequest request,
  ) async {
    final json = await _apiClient.patchJson(
      '/businesses/$businessId/users/$userId',
      body: request.toJson(),
    );
    return User.fromJson(json);
  }

  Future<List<BusinessModule>> listModules(String businessId) async {
    final rawList = await _apiClient.getJsonList(
      '/businesses/$businessId/modules',
    );
    return rawList
        .map((item) => BusinessModule.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<BusinessModule> setModuleEnabled(
    String businessId, {
    required ModuleKey moduleKey,
    required bool enabled,
  }) async {
    final json = await _apiClient.putJson(
      '/businesses/$businessId/modules/${moduleKey.apiValue}',
      body: ModuleStateRequest(enabled: enabled).toJson(),
    );
    return BusinessModule.fromJson(json);
  }
}
