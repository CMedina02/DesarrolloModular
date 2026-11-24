import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/categories/application/categories_providers.dart';
import 'package:inventario_comercial/features/products/application/product_validators.dart';
import 'package:inventario_comercial/features/products/application/products_providers.dart';

/// Create/Edit product dialog for `ADMIN`.
///
/// Keeps prices and quantities as exact decimal strings, displays
/// `stock_quantity` as read-only, and preserves form inputs on server error.
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({
    super.key,
    required this.businessId,
    this.existing,
  });

  final String businessId;
  final Product? existing;

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _skuController;
  late final TextEditingController _nameController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _minStockController;

  String? _selectedCategoryId;
  late ProductUnit _selectedUnit;
  late bool _isActive;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _skuController = TextEditingController(text: existing?.sku ?? '');
    _nameController = TextEditingController(text: existing?.name ?? '');
    _costPriceController =
        TextEditingController(text: existing?.costPrice ?? '');
    _salePriceController =
        TextEditingController(text: existing?.salePrice ?? '');
    _minStockController = TextEditingController(text: existing?.minStock ?? '');
    _selectedCategoryId = existing?.categoryId;
    _selectedUnit = existing?.unit ?? ProductUnit.pza;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _costPriceController.dispose();
    _salePriceController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  String? _optionalTrim(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
      setState(() => _errorMessage = 'Selecciona una categoría.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(productsRepositoryProvider);
      if (widget.existing == null) {
        final created = await repo.createProduct(
          widget.businessId,
          ProductCreateRequest(
            categoryId: _selectedCategoryId!,
            sku: _skuController.text.trim(),
            name: _nameController.text.trim(),
            unit: _selectedUnit,
            costPrice: _optionalTrim(_costPriceController),
            salePrice: _optionalTrim(_salePriceController),
            minStock: _optionalTrim(_minStockController),
            isActive: _isActive,
          ),
        );
        if (mounted) Navigator.of(context).pop(created);
      } else {
        final updated = await repo.updateProduct(
          widget.businessId,
          widget.existing!.id,
          ProductUpdateRequest(
            categoryId: _selectedCategoryId,
            sku: _skuController.text.trim(),
            name: _nameController.text.trim(),
            unit: _selectedUnit,
            costPrice: _optionalTrim(_costPriceController),
            salePrice: _optionalTrim(_salePriceController),
            minStock: _optionalTrim(_minStockController),
            isActive: _isActive,
          ),
        );
        if (mounted) Navigator.of(context).pop(updated);
      }
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.userMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = 'No se pudo guardar el producto.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync =
        ref.watch(categorySelectorListProvider(widget.businessId));
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEdit ? 'Editar producto' : 'Nuevo producto'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    key: const Key('product_form_error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                categoriesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(
                    error is ApiException
                        ? error.userMessage
                        : 'No se pudieron cargar las categorías.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  data: (categories) {
                    if (categories.isEmpty) {
                      return const Text(
                        'Primero crea al menos una categoría en tu empresa.',
                      );
                    }
                    final validSelected = categories
                            .any((c) => c.id == _selectedCategoryId)
                        ? _selectedCategoryId
                        : categories.first.id;
                    _selectedCategoryId = validSelected;

                    return DropdownButtonFormField<String>(
                      key: const Key('product_category_field'),
                      initialValue: validSelected,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: categories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) =>
                              setState(() => _selectedCategoryId = value),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product_sku_field'),
                  controller: _skuController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Ingresa el SKU.';
                    if (trimmed.length > 60) return 'Máximo 60 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product_name_field'),
                  controller: _nameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del producto',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Ingresa el nombre.';
                    if (trimmed.length > 180) return 'Máximo 180 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProductUnit>(
                  key: const Key('product_unit_field'),
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    border: OutlineInputBorder(),
                    helperText: 'PZA y CAJA requieren cantidades enteras.',
                  ),
                  items: ProductUnit.values
                      .map(
                        (u) => DropdownMenuItem<ProductUnit>(
                          value: u,
                          child: Text(u.apiValue),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _submitting
                      ? null
                      : (unit) {
                          if (unit != null) {
                            setState(() => _selectedUnit = unit);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product_cost_price_field'),
                  controller: _costPriceController,
                  enabled: !_submitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de costo (ej. 12.50)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => ProductValidators.validatePrice(value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product_sale_price_field'),
                  controller: _salePriceController,
                  enabled: !_submitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta (ej. 19.90)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => ProductValidators.validatePrice(value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product_min_stock_field'),
                  controller: _minStockController,
                  enabled: !_submitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Stock mínimo (hasta 3 decimales)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => ProductValidators.validateQuantity(
                    value,
                    unit: _selectedUnit,
                    allowZero: true,
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Existencia actual (solo lectura)',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    widget.existing?.stockQuantity ?? '0.000',
                    key: const Key('product_readonly_stock'),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Producto activo'),
                  value: _isActive,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('product_save_button'),
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Guardar cambios' : 'Crear'),
        ),
      ],
    );
  }
}
