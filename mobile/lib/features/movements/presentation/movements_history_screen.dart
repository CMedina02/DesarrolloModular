import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/movement.dart';
import 'package:inventario_comercial/core/models/product.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/movements/application/movements_providers.dart';

/// Read-only movement history screen for `ADMIN` (`GET /inventory/movements`).
class MovementsHistoryScreen extends ConsumerStatefulWidget {
  const MovementsHistoryScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  ConsumerState<MovementsHistoryScreen> createState() =>
      _MovementsHistoryScreenState();
}

class _MovementsHistoryScreenState
    extends ConsumerState<MovementsHistoryScreen> {
  static const int _pageSize = 25;

  String? _selectedProductId;
  MovementType? _selectedType;
  DateTime? _fromDate;
  DateTime? _toDate;
  int _offset = 0;

  String get _businessId => widget.currentUser.businessId!;

  bool get _hasInvalidDateRange =>
      _fromDate != null && _toDate != null && !_toDate!.isAfter(_fromDate!);

  bool get _hasActiveFilters =>
      _selectedProductId != null ||
      _selectedType != null ||
      _fromDate != null ||
      _toDate != null;

  MovementsHistoryQuery get _currentQuery => MovementsHistoryQuery(
        businessId: _businessId,
        limit: _pageSize,
        offset: _offset,
        productId: _selectedProductId,
        movementType: _selectedType,
        from: _fromDate,
        to: _toDate,
      );

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _fromDate : _toDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    final normalizedUtc = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (isFrom) {
        _fromDate = normalizedUtc;
      } else {
        _toDate = normalizedUtc;
      }
      _offset = 0;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedProductId = null;
      _selectedType = null;
      _fromDate = null;
      _toDate = null;
      _offset = 0;
    });
  }

  String _formatDateLabel(DateTime? date) {
    if (date == null) return 'Sin fecha';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatTimestamp(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm UTC';
  }

  Future<void> _openDetail(
    Movement movement,
    Map<String, Product> productMap,
  ) async {
    final product = productMap[movement.productId];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detalle de movimiento'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine(
                  label: 'Tipo',
                  value: movement.movementType.apiValue,
                ),
                _DetailLine(
                  label: 'Fecha (RFC 3339)',
                  value: movement.createdAt.toUtc().toIso8601String(),
                ),
                _DetailLine(
                  label: 'Producto',
                  value: product != null
                      ? '${product.name} (${product.sku})'
                      : movement.productId,
                ),
                _DetailLine(label: 'Autor (user_id)', value: movement.userId),
                _DetailLine(
                  label: 'Saldo anterior',
                  value: movement.stockBefore,
                ),
                _DetailLine(label: 'Delta', value: movement.quantityDelta),
                _DetailLine(
                  label: 'Saldo posterior',
                  value: movement.stockAfter,
                ),
                _DetailLine(
                  label: 'Motivo',
                  value: movement.reason ?? 'Sin motivo',
                ),
                _DetailLine(label: 'Movimiento ID', value: movement.id),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser.role != UserRole.admin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El historial de movimientos está reservado para el rol ADMIN.',
          ),
        ),
      );
    }

    final productsAsync =
        ref.watch(historyProductsSelectorProvider(_businessId));
    final productMap = <String, Product>{
      for (final p in productsAsync.asData?.value ?? const <Product>[]) p.id: p,
    };
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String?>(
                  key: const Key('history_product_filter'),
                  initialValue: _selectedProductId,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Producto',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...productMap.values.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(
                          '${p.name}${p.isActive ? '' : ' (Inactivo)'}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedProductId = value;
                      _offset = 0;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<MovementType?>(
                  key: const Key('history_type_filter'),
                  initialValue: _selectedType,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<MovementType?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem<MovementType?>(
                      value: MovementType.entry,
                      child: Text('IN (Entrada)'),
                    ),
                    DropdownMenuItem<MovementType?>(
                      value: MovementType.exit,
                      child: Text('OUT (Salida)'),
                    ),
                    DropdownMenuItem<MovementType?>(
                      value: MovementType.adjustment,
                      child: Text('ADJUSTMENT (Ajuste)'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value;
                      _offset = 0;
                    });
                  },
                ),
              ),
              OutlinedButton.icon(
                key: const Key('history_from_button'),
                onPressed: () => _pickDate(isFrom: true),
                icon: const Icon(Icons.date_range, size: 18),
                label: Text('Desde: ${_formatDateLabel(_fromDate)}'),
              ),
              OutlinedButton.icon(
                key: const Key('history_to_button'),
                onPressed: () => _pickDate(isFrom: false),
                icon: const Icon(Icons.event, size: 18),
                label: Text('Hasta (excl.): ${_formatDateLabel(_toDate)}'),
              ),
              if (_hasActiveFilters)
                TextButton.icon(
                  key: const Key('history_clear_filters_button'),
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpiar filtros'),
                ),
            ],
          ),
        ),
        if (_hasInvalidDateRange)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              key: const Key('history_date_error'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'La fecha "Hasta" (exclusiva) debe ser posterior a la fecha "Desde" (inclusiva).',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        Expanded(
          child: _hasInvalidDateRange
              ? const SizedBox.shrink()
              : _HistoryListBody(
                  query: _currentQuery,
                  productMap: productMap,
                  offset: _offset,
                  pageSize: _pageSize,
                  formatTimestamp: _formatTimestamp,
                  onTapItem: (m) => _openDetail(m, productMap),
                  onPreviousPage: () => setState(
                    () => _offset = (_offset - _pageSize).clamp(0, _offset),
                  ),
                  onNextPage: () => setState(() => _offset += _pageSize),
                ),
        ),
      ],
    );
  }
}

class _HistoryListBody extends ConsumerWidget {
  const _HistoryListBody({
    required this.query,
    required this.productMap,
    required this.offset,
    required this.pageSize,
    required this.formatTimestamp,
    required this.onTapItem,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final MovementsHistoryQuery query;
  final Map<String, Product> productMap;
  final int offset;
  final int pageSize;
  final String Function(DateTime) formatTimestamp;
  final ValueChanged<Movement> onTapItem;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(movementsHistoryProvider(query));
    final theme = Theme.of(context);

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        final message = error is ApiException
            ? error.userMessage
            : 'No se pudo consultar el historial de movimientos.';
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
                  key: const Key('history_retry_button'),
                  onPressed: () =>
                      ref.invalidate(movementsHistoryProvider(query)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        );
      },
      data: (page) {
        if (page.items.isEmpty && offset == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No hay movimientos registrados para los filtros seleccionados.',
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
                padding: const EdgeInsets.all(16),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final movement = page.items[index];
                  final product = productMap[movement.productId];
                  final productLabel = product != null
                      ? '${product.name} (${product.sku})'
                      : movement.productId;

                  return Card(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: ListTile(
                      onTap: () => onTapItem(movement),
                      title: Text(
                        '${movement.movementType.apiValue} · $productLabel',
                      ),
                      subtitle: Text(
                        '${formatTimestamp(movement.createdAt)}\n'
                        'Antes: ${movement.stockBefore} · '
                        'Delta: ${movement.quantityDelta} · '
                        'Después: ${movement.stockAfter}'
                        '${movement.reason != null ? '\nMotivo: ${movement.reason}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
            if (offset > 0 || page.hasMore)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      key: const Key('history_prev_page'),
                      onPressed: offset > 0 ? onPreviousPage : null,
                      child: const Text('Anterior'),
                    ),
                    Text('Mostrando desde ${offset + 1}'),
                    OutlinedButton(
                      key: const Key('history_next_page'),
                      onPressed: page.hasMore ? onNextPage : null,
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
