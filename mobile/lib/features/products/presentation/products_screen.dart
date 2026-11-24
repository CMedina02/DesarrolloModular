import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/categories/application/categories_providers.dart';
import 'package:inventario_comercial/features/products/application/products_providers.dart';
import 'package:inventario_comercial/features/products/presentation/product_detail_dialog.dart';
import 'package:inventario_comercial/features/products/presentation/product_form_dialog.dart';
import 'package:inventario_comercial/features/products/presentation/products_skeleton.dart';

/// Product catalog screen with filters, pagination, skeleton loading, and CRUD
/// for `ADMIN` (read-only active catalog for `EMPLOYEE`).
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  static const int _pageSize = 25;

  String? _selectedCategoryId;
  bool? _selectedIsActive;
  bool _lowStockOnly = false;
  int _offset = 0;
  String? _actionError;

  bool get _canWrite => widget.currentUser.role == UserRole.admin;
  String get _businessId => widget.currentUser.businessId!;

  ProductsPageQuery get _currentQuery => ProductsPageQuery(
        businessId: _businessId,
        limit: _pageSize,
        offset: _offset,
        categoryId: _selectedCategoryId,
        isActive: _canWrite ? _selectedIsActive : true,
        lowStock: _lowStockOnly,
      );

  void _refreshCatalog({String? productId}) {
    ref.invalidate(productsPageProvider(_currentQuery));
    ref.invalidate(activeProductsSelectorProvider(_businessId));
    if (productId != null) {
      ref.invalidate(
        productDetailProvider((businessId: _businessId, productId: productId)),
      );
    }
  }

  Future<void> _openForm({Product? existing}) async {
    setState(() => _actionError = null);
    final saved = await showDialog<Product>(
      context: context,
      builder: (_) => ProductFormDialog(
        businessId: _businessId,
        existing: existing,
      ),
    );
    if (saved != null) {
      _refreshCatalog(productId: saved.id);
    }
  }

  Future<void> _deactivate(Product product) async {
    setState(() => _actionError = null);

    try {
      await ref
          .read(productsRepositoryProvider)
          .deactivateProduct(_businessId, product.id);
      _refreshCatalog(productId: product.id);
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        return;
      }
      if (e.isForbidden) {
        ref.invalidate(businessModulesProvider(_businessId));
      }
      if (mounted) {
        setState(() => _actionError = e.userMessage);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'No se pudo desactivar el producto.');
      }
    }
  }

  Future<void> _openDetail(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProductDetailDialog(
        businessId: _businessId,
        productId: product.id,
        canWrite: _canWrite,
        onEdit: (p) => _openForm(existing: p),
        onDeactivate: _deactivate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(productsPageProvider(_currentQuery));
    final categoriesAsync =
        ref.watch(categorySelectorListProvider(_businessId));
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('create_product_fab'),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo producto'),
            )
          : null,
      body: Column(
        children: [
          if (_actionError != null)
            MaterialBanner(
              key: const Key('product_action_error'),
              backgroundColor: theme.colorScheme.errorContainer,
              content: Text(
                _actionError!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _actionError = null),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: categoriesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (categories) => DropdownButtonFormField<String?>(
                      key: const Key('products_category_filter'),
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ...categories.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                          _offset = 0;
                        });
                      },
                    ),
                  ),
                ),
                if (_canWrite)
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<bool?>(
                      key: const Key('products_status_filter'),
                      initialValue: _selectedIsActive,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<bool?>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        DropdownMenuItem<bool?>(
                          value: true,
                          child: Text('Activos'),
                        ),
                        DropdownMenuItem<bool?>(
                          value: false,
                          child: Text('Inactivos'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedIsActive = value;
                          _offset = 0;
                        });
                      },
                    ),
                  ),
                FilterChip(
                  key: const Key('products_low_stock_filter'),
                  label: const Text('Stock bajo'),
                  selected: _lowStockOnly,
                  onSelected: (selected) {
                    setState(() {
                      _lowStockOnly = selected;
                      _offset = 0;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: pageAsync.when(
              loading: () => const ProductsLoadingSkeleton(),
              error: (error, _) {
                final message = error is ApiException
                    ? error.userMessage
                    : 'No se pudo cargar el catálogo de productos.';
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 40,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(message, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('products_retry_button'),
                          onPressed: _refreshCatalog,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              data: (page) {
                if (page.items.isEmpty && _offset == 0) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No hay productos que coincidan con los filtros.',
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: page.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final product = page.items[index];
                          return Card(
                            color: theme.colorScheme.surfaceContainerLow,
                            child: ListTile(
                              title: Text(product.name),
                              subtitle: Text(
                                'SKU: ${product.sku} · Venta: \$${product.salePrice} · '
                                'Stock: ${product.stockQuantity} ${product.unit.apiValue}'
                                '${product.isActive ? '' : ' · Inactivo'}',
                              ),
                              onTap: () => _openDetail(product),
                              trailing: _canWrite
                                  ? Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          key: Key('edit_product_${product.id}'),
                                          tooltip: 'Editar producto',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () =>
                                              _openForm(existing: product),
                                        ),
                                        if (product.isActive)
                                          IconButton(
                                            key: Key(
                                              'deactivate_product_${product.id}',
                                            ),
                                            tooltip: 'Desactivar producto',
                                            icon: const Icon(
                                              Icons.visibility_off_outlined,
                                            ),
                                            onPressed: () =>
                                                _deactivate(product),
                                          ),
                                      ],
                                    )
                                  : const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_offset > 0 || page.hasMore)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton(
                              key: const Key('products_prev_page'),
                              onPressed: _offset > 0
                                  ? () => setState(
                                        () => _offset = (_offset - _pageSize)
                                            .clamp(0, _offset),
                                      )
                                  : null,
                              child: const Text('Anterior'),
                            ),
                            Text('Mostrando desde ${_offset + 1}'),
                            OutlinedButton(
                              key: const Key('products_next_page'),
                              onPressed: page.hasMore
                                  ? () =>
                                      setState(() => _offset += _pageSize)
                                  : null,
                              child: const Text('Siguiente'),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
