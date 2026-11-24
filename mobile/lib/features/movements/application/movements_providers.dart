import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/movement.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/movements/data/movements_repository.dart';
import 'package:inventario_comercial/features/products/application/products_providers.dart';

final movementsRepositoryProvider = Provider<MovementsRepository>(
  (ref) => MovementsRepository(ref.watch(apiClientProvider)),
);

@immutable
class MovementsHistoryQuery {
  const MovementsHistoryQuery({
    required this.businessId,
    this.limit = 25,
    this.offset = 0,
    this.productId,
    this.movementType,
    this.from,
    this.to,
  });

  final String businessId;
  final int limit;
  final int offset;
  final String? productId;
  final MovementType? movementType;
  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovementsHistoryQuery &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          limit == other.limit &&
          offset == other.offset &&
          productId == other.productId &&
          movementType == other.movementType &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(
        businessId,
        limit,
        offset,
        productId,
        movementType,
        from,
        to,
      );
}

final movementsHistoryProvider = FutureProvider.autoDispose
    .family<PaginatedList<Movement>, MovementsHistoryQuery>(
  retry: (_, _) => null,
  (ref, query) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(movementsRepositoryProvider).listMovements(
            query.businessId,
            limit: query.limit,
            offset: query.offset,
            productId: query.productId,
            movementType: query.movementType,
            from: query.from,
            to: query.to,
          ),
    );
  },
);

/// Loads all products (including inactive) for the `ADMIN` history filter.
final historyProductsSelectorProvider =
    FutureProvider.family<List<Product>, String>(
  (ref, businessId) async {
    final page = await runWithSessionGuard(
      ref,
      () => ref
          .watch(productsRepositoryProvider)
          .listProducts(businessId, limit: 100, offset: 0),
    );
    return page.items;
  },
);
