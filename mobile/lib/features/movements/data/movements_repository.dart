import 'package:inventario_comercial/core/models/movement.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Repository for `POST /businesses/{business_id}/inventory/movements`.
///
/// Write operations are never retried automatically to prevent duplicate stock
/// changes.
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
}
