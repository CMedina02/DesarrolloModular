import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/business.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/paginated_list.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/data/admin_repository.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Selected business UUID for `PLATFORM_ADMIN` administration screens.
class SelectedBusinessIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? businessId) {
    state = businessId;
  }
}

final selectedBusinessIdProvider =
    NotifierProvider<SelectedBusinessIdNotifier, String?>(
  SelectedBusinessIdNotifier.new,
);

/// Handles `401` responses (e.g. business or user deactivated mid-session) by
/// invalidating the local session and returning to login.
Future<T> runWithSessionGuard<T>(
  Ref ref,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on ApiException catch (e) {
    if (e.isAuthFailure) {
      await ref.read(authControllerProvider.notifier).handleSessionExpired(
            message: e.userMessage,
          );
    }
    rethrow;
  }
}

/// Paginated list of businesses (`PLATFORM_ADMIN`).
final businessesProvider = FutureProvider<PaginatedList<Business>>((ref) async {
  return runWithSessionGuard(
    ref,
    () => ref.watch(adminRepositoryProvider).listBusinesses(),
  );
});

/// Paginated list of users for a given [businessId].
final businessUsersProvider =
    FutureProvider.family<PaginatedList<User>, String>((ref, businessId) async {
  return runWithSessionGuard(
    ref,
    () => ref.watch(adminRepositoryProvider).listUsers(businessId),
  );
});

/// Module states for a given [businessId] (`GET /businesses/{id}/modules`).
final businessModulesProvider =
    FutureProvider.family<List<BusinessModule>, String>(
  (ref, businessId) async {
    return runWithSessionGuard(
      ref,
      () => ref.watch(adminRepositoryProvider).listModules(businessId),
    );
  },
);

/// Derived helper indicating whether `inventory` is enabled for [businessId].
final isInventoryEnabledProvider = Provider.family<AsyncValue<bool>, String>(
  (ref, businessId) {
    final modulesAsync = ref.watch(businessModulesProvider(businessId));
    return modulesAsync.whenData((modules) {
      for (final module in modules) {
        if (module.key == ModuleKey.inventory) {
          return module.enabled;
        }
      }
      return false;
    });
  },
);
