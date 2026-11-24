import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/movement.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Repository for `/businesses/{business_id}/inventory/movements`.
///
/// Write operations are never retried automatically to prevent duplicate stock
/// changes. History (`GET`) requires backend B10 in live environments.
class MovementsRepository {
  MovementsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<Movement> createMovement(
    String businessId,
    MovementCreateRequest request,
  ) async {
    final json = await _apiClient.postJson(
      '/businesses/$businessId/inventory/movements',
      body: request.toJson(),
    );
    return Movement.fromJson(json);
  }

  /// Queries movement history (`ADMIN` only).
  ///
  /// [from] is inclusive and [to] is exclusive, formatted as RFC 3339 UTC.
  Future<PaginatedList<Movement>> listMovements(
    String businessId, {
    int limit = 25,
    int offset = 0,
    String? productId,
    MovementType? movementType,
    DateTime? from,
    DateTime? to,
  }) async {
    final json = await _apiClient.getJson(
      '/businesses/$businessId/inventory/movements',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
        if (movementType != null) 'movement_type': movementType.apiValue,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
    );
    return PaginatedList.fromJson(json, Movement.fromJson);
  }
}
