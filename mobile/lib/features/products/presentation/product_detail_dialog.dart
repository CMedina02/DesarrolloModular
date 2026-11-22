import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/products/application/products_providers.dart';

/// Product detail dialog fetching `GET /businesses/{business_id}/inventory/products/{id}`.
class ProductDetailDialog extends ConsumerWidget {
  const ProductDetailDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.canWrite,
    this.onEdit,
    this.onDeactivate,
  });

  final String businessId;
  final String productId;
  final bool canWrite;
  final ValueChanged<Product>? onEdit;
  final ValueChanged<Product>? onDeactivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      productDetailProvider((businessId: businessId, productId: productId)),
    );

    return AlertDialog(
      title: const Text('Detalle de producto'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: detailAsync.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            error is ApiException
                ? error.userMessage
                : 'No se pudo cargar el detalle del producto.',
          ),
          data: (product) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Nombre', value: product.name),
                _DetailRow(label: 'SKU', value: product.sku),
                _DetailRow(label: 'Unidad', value: product.unit.apiValue),
                _DetailRow(label: 'Precio costo', value: product.costPrice),
                _DetailRow(label: 'Precio venta', value: product.salePrice),
                _DetailRow(label: 'Stock mínimo', value: product.minStock),
                _DetailRow(
                  label: 'Existencia actual',
                  value: product.stockQuantity,
                ),
                _DetailRow(
                  label: 'Estado',
                  value: product.isActive ? 'Activo' : 'Inactivo',
                ),
                _DetailRow(label: 'Categoría ID', value: product.categoryId),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (canWrite && detailAsync.asData?.value != null) ...[
          if (detailAsync.asData!.value.isActive && onDeactivate != null)
            TextButton(
              key: const Key('detail_deactivate_product_button'),
              onPressed: () {
                final product = detailAsync.asData!.value;
                Navigator.of(context).pop();
                onDeactivate!(product);
              },
              child: const Text('Desactivar'),
            ),
          if (onEdit != null)
            OutlinedButton(
              key: const Key('detail_edit_product_button'),
              onPressed: () {
                final product = detailAsync.asData!.value;
                Navigator.of(context).pop();
                onEdit!(product);
              },
              child: const Text('Editar'),
            ),
        ],
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
