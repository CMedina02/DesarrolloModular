import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/movement.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/movements/application/movements_providers.dart';
import 'package:inventario_comercial/features/products/application/product_validators.dart';
import 'package:inventario_comercial/features/products/application/products_providers.dart';

/// Stock movement registration screen (`IN`, `OUT`, and `ADMIN`-only `ADJUSTMENT`).
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _selectedProductId;
  MovementType _movementType = MovementType.entry;
  bool _submitting = false;
  bool _verifyingStock = false;

  /// Latest server-confirmed balance per product ID so UI never loses it on 409.
  final Map<String, String> _confirmedStockByProduct = {};

  Movement? _lastMovement;
  String? _errorMessage;
  bool _uncertainConfirmation = false;

  bool get _canAdjust => widget.currentUser.role == UserRole.admin;
  String get _businessId => widget.currentUser.businessId!;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  List<MovementType> get _allowedTypes => _canAdjust
      ? const [MovementType.entry, MovementType.exit, MovementType.adjustment]
      : const [MovementType.entry, MovementType.exit];

  Future<void> _submit(Product product) async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _uncertainConfirmation = false;
      _lastMovement = null;
    });

    final quantityText = _quantityController.text.trim();
    final reasonText = _reasonController.text.trim();

    final MovementCreateRequest request = switch (_movementType) {
      MovementType.entry => StockEntryRequest(
          productId: product.id,
          quantity: quantityText,
          reason: reasonText.isEmpty ? null : reasonText,
        ),
      MovementType.exit => StockExitRequest(
          productId: product.id,
          quantity: quantityText,
          reason: reasonText,
        ),
      MovementType.adjustment => StockAdjustmentRequest(
          productId: product.id,
          countedQuantity: quantityText,
          reason: reasonText,
        ),
    };

    try {
      final movement = await ref
          .read(movementsRepositoryProvider)
          .createMovement(_businessId, request);

      if (!mounted) return;

      setState(() {
        _submitting = false;
        _lastMovement = movement;
        _confirmedStockByProduct[product.id] = movement.stockAfter;
        _quantityController.clear();
        _reasonController.clear();
      });

      // Refresh catalog, product detail, and history caches.
      ref.invalidate(activeProductsSelectorProvider(_businessId));
      ref.invalidate(
        productDetailProvider((businessId: _businessId, productId: product.id)),
      );
      ref.invalidate(productsPageProvider);
      ref.invalidate(movementsHistoryProvider);
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
      if (!mounted) return;

      setState(() {
        _submitting = false;
        if (e.isConnectivityIssue) {
          _uncertainConfirmation = true;
          _errorMessage =
              'Se perdió la conexión después de enviar el movimiento. '
              'La confirmación es incierta: verifica el saldo actual antes de repetir la operación.';
        } else {
          _errorMessage = e.userMessage;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uncertainConfirmation = true;
        _errorMessage =
            'No se pudo confirmar si el movimiento fue registrado. '
            'Verifica el saldo actual antes de reintentar.';
      });
    }
  }

  Future<void> _verifyCurrentStock(String productId) async {
    if (_verifyingStock) return;
    setState(() => _verifyingStock = true);

    try {
      final refreshed = await ref
          .read(productsRepositoryProvider)
          .getProduct(_businessId, productId);
      if (!mounted) return;
      setState(() {
        _confirmedStockByProduct[productId] = refreshed.stockQuantity;
        _uncertainConfirmation = false;
        _errorMessage = null;
      });
      ref.invalidate(activeProductsSelectorProvider(_businessId));
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        return;
      }
      if (mounted) {
        setState(() => _errorMessage = e.userMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _verifyingStock = false);
      }
    }
  }

  String _labelForType(MovementType type) {
    switch (type) {
      case MovementType.entry:
        return 'Entrada';
      case MovementType.exit:
        return 'Salida';
      case MovementType.adjustment:
        return 'Ajuste';
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync =
        ref.watch(activeProductsSelectorProvider(_businessId));
    final theme = Theme.of(context);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is ApiException
                    ? error.userMessage
                    : 'No se pudieron cargar los productos activos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(activeProductsSelectorProvider(_businessId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay productos activos disponibles para registrar movimientos.',
              ),
            ),
          );
        }

        final selectedProduct = products.firstWhere(
          (p) => p.id == _selectedProductId,
          orElse: () => products.first,
        );
        _selectedProductId = selectedProduct.id;

        final confirmedStock = _confirmedStockByProduct[selectedProduct.id] ??
            selectedProduct.stockQuantity;
        final isAdjustment = _movementType == MovementType.adjustment;
        final reasonRequired = _movementType != MovementType.entry;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Registrar movimiento de stock',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('movement_product_selector'),
                      initialValue: selectedProduct.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Producto activo',
                        border: OutlineInputBorder(),
                      ),
                      items: products
                          .map(
                            (p) => DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(
                                '${p.name} (${p.sku}) · ${p.unit.apiValue}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedProductId = value;
                                  _errorMessage = null;
                                  _uncertainConfirmation = false;
                                  _lastMovement = null;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        leading: const Icon(Icons.inventory_outlined),
                        title: const Text('Último saldo confirmado'),
                        subtitle: Text(
                          '$confirmedStock ${selectedProduct.unit.apiValue}',
                          key: const Key('movement_confirmed_stock'),
                          style: theme.textTheme.titleMedium,
                        ),
                        trailing: IconButton(
                          key: const Key('verify_stock_button'),
                          tooltip: 'Verificar saldo actual',
                          onPressed: _verifyingStock
                              ? null
                              : () => _verifyCurrentStock(selectedProduct.id),
                          icon: _verifyingStock
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<MovementType>(
                      key: const Key('movement_type_selector'),
                      segments: _allowedTypes
                          .map(
                            (type) => ButtonSegment<MovementType>(
                              value: type,
                              label: Text(_labelForType(type)),
                            ),
                          )
                          .toList(growable: false),
                      selected: {_movementType},
                      onSelectionChanged: _submitting
                          ? null
                          : (selection) {
                              setState(() {
                                _movementType = selection.first;
                                _errorMessage = null;
                                _uncertainConfirmation = false;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('movement_quantity_field'),
                      controller: _quantityController,
                      enabled: !_submitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: isAdjustment
                            ? 'Existencia física contada (${selectedProduct.unit.apiValue})'
                            : 'Cantidad (${selectedProduct.unit.apiValue})',
                        helperText: selectedProduct.unit.requiresIntegerQuantity
                            ? 'La unidad ${selectedProduct.unit.apiValue} solo admite enteros.'
                            : 'Admite hasta 3 decimales.',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => ProductValidators.validateQuantity(
                        value,
                        unit: selectedProduct.unit,
                        allowZero: isAdjustment,
                        requiredField: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('movement_reason_field'),
                      controller: _reasonController,
                      enabled: !_submitting,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: reasonRequired
                            ? 'Motivo (obligatorio)'
                            : 'Motivo (opcional)',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (reasonRequired && (value?.trim().isEmpty ?? true)) {
                          return 'El motivo es obligatorio para ${_labelForType(_movementType).toLowerCase()}.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null) ...[
                      Container(
                        key: _uncertainConfirmation
                            ? const Key('movement_uncertain_banner')
                            : const Key('movement_error_banner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _uncertainConfirmation
                              ? theme.colorScheme.tertiaryContainer
                              : theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: _uncertainConfirmation
                                    ? theme.colorScheme.onTertiaryContainer
                                    : theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            if (_uncertainConfirmation) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                key: const Key('uncertain_verify_stock_button'),
                                onPressed: _verifyingStock
                                    ? null
                                    : () => _verifyCurrentStock(
                                          selectedProduct.id,
                                        ),
                                icon: const Icon(Icons.sync),
                                label: const Text('Verificar saldo actual'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_lastMovement != null) ...[
                      Card(
                        key: const Key('movement_success_card'),
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.45),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Movimiento registrado (${_lastMovement!.movementType.apiValue})',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Saldo anterior: ${_lastMovement!.stockBefore} → '
                                'Delta: ${_lastMovement!.quantityDelta} → '
                                'Saldo actual: ${_lastMovement!.stockAfter}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      key: const Key('movement_submit_button'),
                      onPressed:
                          _submitting ? null : () => _submit(selectedProduct),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _submitting
                            ? 'Registrando...'
                            : 'Registrar ${_labelForType(_movementType).toLowerCase()}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
