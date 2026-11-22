import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/products/data/products_repository.dart';

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => ProductsRepository(ref.watch(apiClientProvider)),
);

@immutable
class ProductsPageQuery {
  const ProductsPageQuery({
    required this.businessId,
    this.limit = 25,
    this.offset = 0,
    this.categoryId,
    this.isActive,
    this.lowStock = false,
  });

  final String businessId;
  final int limit;
  final int offset;
  final String? categoryId;
  final bool? isActive;
  final bool lowStock;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductsPageQuery &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          limit == other.limit &&
          offset == other.offset &&
          categoryId == other.categoryId &&
          isActive == other.isActive &&
          lowStock == other.lowStock;

  @override
  int get hashCode =>
      Object.hash(businessId, limit, offset, categoryId, isActive, lowStock);
}

final productsPageProvider =
    FutureProvider.family<PaginatedList<Product>, ProductsPageQuery>(
  (ref, query) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(productsRepositoryProvider).listProducts(
            query.businessId,
            limit: query.limit,
            offset: query.offset,
            categoryId: query.categoryId,
            isActive: query.isActive,
            lowStock: query.lowStock,
          ),
    );
  },
);

final productDetailProvider = FutureProvider.family<Product,
    ({String businessId, String productId})>(
  (ref, params) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(productsRepositoryProvider).getProduct(
            params.businessId,
            params.productId,
          ),
    );
  },
);

/// Active products list for selectors in movements & history (F07/F08).
final activeProductsSelectorProvider =
    FutureProvider.family<List<Product>, String>(
  (ref, businessId) async {
    final page = await runWithSessionGuard(
      ref,
      () => ref.watch(productsRepositoryProvider).listProducts(
            businessId,
            limit: 100,
            offset: 0,
            isActive: true,
          ),
    );
    return page.items;
  },
);
