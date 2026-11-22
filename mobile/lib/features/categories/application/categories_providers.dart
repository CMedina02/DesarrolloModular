import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/category.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/categories/data/categories_repository.dart';

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(ref.watch(apiClientProvider)),
);

@immutable
class CategoriesPageQuery {
  const CategoriesPageQuery({
    required this.businessId,
    this.limit = 25,
    this.offset = 0,
  });

  final String businessId;
  final int limit;
  final int offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoriesPageQuery &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(businessId, limit, offset);
}

/// Paginated categories list for a business.
final categoriesPageProvider =
    FutureProvider.family<PaginatedList<Category>, CategoriesPageQuery>(
  (ref, query) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(categoriesRepositoryProvider).listCategories(
            query.businessId,
            limit: query.limit,
            offset: query.offset,
          ),
    );
  },
);

/// Category detail (`GET /businesses/{business_id}/inventory/categories/{id}`).
final categoryDetailProvider = FutureProvider.family<Category,
    ({String businessId, String categoryId})>(
  (ref, params) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(categoriesRepositoryProvider).getCategory(
            params.businessId,
            params.categoryId,
          ),
    );
  },
);

/// Categories list for dropdown selectors (e.g. product filters & forms in F06).
final categorySelectorListProvider =
    FutureProvider.family<List<Category>, String>(
  (ref, businessId) async {
    final page = await runWithSessionGuard(
      ref,
      () => ref
          .watch(categoriesRepositoryProvider)
          .listCategories(businessId, limit: 100, offset: 0),
    );
    return page.items;
  },
);
