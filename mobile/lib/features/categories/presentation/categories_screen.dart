import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/category.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/categories/application/categories_providers.dart';

/// Categories list, detail, and CRUD (`ADMIN` write, `EMPLOYEE` read-only).
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  static const int _pageSize = 25;
  int _offset = 0;
  String? _actionError;

  bool get _canWrite => widget.currentUser.role == UserRole.admin;
  String get _businessId => widget.currentUser.businessId!;

  CategoriesPageQuery get _currentQuery => CategoriesPageQuery(
        businessId: _businessId,
        limit: _pageSize,
        offset: _offset,
      );

  void _refreshCategories() {
    ref.invalidate(categoriesPageProvider(_currentQuery));
    ref.invalidate(categorySelectorListProvider(_businessId));
  }

  Future<void> _openFormDialog({Category? existing}) async {
    setState(() => _actionError = null);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryFormDialog(
        businessId: _businessId,
        existing: existing,
      ),
    );
    if (saved == true) {
      _refreshCategories();
    }
  }

  Future<void> _openDetailDialog(Category category) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoryDetailDialog(
        businessId: _businessId,
        categoryId: category.id,
      ),
    );
  }

  Future<void> _confirmAndDelete(Category category) async {
    setState(() => _actionError = null);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Deseas eliminar "${category.name}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_delete_category_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(categoriesRepositoryProvider)
          .deleteCategory(_businessId, category.id);
      _refreshCategories();
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
        setState(() {
          _actionError = 'No se pudo eliminar la categoría.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(categoriesPageProvider(_currentQuery));
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('create_category_fab'),
              onPressed: () => _openFormDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría'),
            )
          : null,
      body: Column(
        children: [
          if (_actionError != null)
            MaterialBanner(
              key: const Key('category_action_error'),
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
          Expanded(
            child: pageAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) {
                final message = error is ApiException
                    ? error.userMessage
                    : 'No se pudieron cargar las categorías.';
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
                          onPressed: _refreshCategories,
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
                            Icons.category_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          const Text('No hay categorías registradas todavía.'),
                          if (_canWrite) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _openFormDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Crear primera categoría'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: page.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final category = page.items[index];
                          return Card(
                            color: theme.colorScheme.surfaceContainerLow,
                            child: ListTile(
                              leading: const Icon(Icons.category_outlined),
                              title: Text(category.name),
                              subtitle: Text('ID: ${category.id}'),
                              onTap: () => _openDetailDialog(category),
                              trailing: _canWrite
                                  ? Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          key: Key('edit_category_${category.id}'),
                                          tooltip: 'Renombrar categoría',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _openFormDialog(
                                            existing: category,
                                          ),
                                        ),
                                        IconButton(
                                          key: Key(
                                            'delete_category_${category.id}',
                                          ),
                                          tooltip: 'Eliminar categoría',
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () =>
                                              _confirmAndDelete(category),
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

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({
    required this.businessId,
    this.existing,
  });

  final String businessId;
  final Category? existing;

  @override
  ConsumerState<_CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(categoriesRepositoryProvider);
      if (widget.existing == null) {
        await repo.createCategory(widget.businessId, _nameController.text);
      } else {
        await repo.updateCategory(
          widget.businessId,
          widget.existing!.id,
          _nameController.text,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        if (mounted) Navigator.of(context).pop(false);
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
          _errorMessage = 'No se pudo guardar la categoría.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEdit ? 'Renombrar categoría' : 'Nueva categoría'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  key: const Key('category_form_error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('category_name_field'),
                controller: _nameController,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la categoría',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Ingresa un nombre válido (1 a 100 caracteres).';
                  }
                  if (trimmed.length > 100) {
                    return 'El nombre no puede superar 100 caracteres.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('category_save_button'),
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

class _CategoryDetailDialog extends ConsumerWidget {
  const _CategoryDetailDialog({
    required this.businessId,
    required this.categoryId,
  });

  final String businessId;
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      categoryDetailProvider((businessId: businessId, categoryId: categoryId)),
    );

    return AlertDialog(
      title: const Text('Detalle de categoría'),
      content: detailAsync.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Text(
          error is ApiException
              ? error.userMessage
              : 'No se pudo cargar el detalle.',
        ),
        data: (category) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre: ${category.name}'),
            const SizedBox(height: 8),
            SelectableText('ID: ${category.id}'),
            const SizedBox(height: 4),
            SelectableText('Empresa: ${category.businessId}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
