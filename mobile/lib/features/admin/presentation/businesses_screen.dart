import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/business.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';

/// Business management screen for `PLATFORM_ADMIN`.
class BusinessesScreen extends ConsumerWidget {
  const BusinessesScreen({super.key});

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _BusinessFormDialog(),
    );
    if (created == true) {
      ref.invalidate(businessesProvider);
    }
  }

  Future<void> _openEditDialog(
    BuildContext context,
    WidgetRef ref,
    Business business,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _BusinessFormDialog(existing: business),
    );
    if (updated == true) {
      ref.invalidate(businessesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessesAsync = ref.watch(businessesProvider);
    final selectedId = ref.watch(selectedBusinessIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_business_fab'),
        onPressed: () => _openCreateDialog(context, ref),
        icon: const Icon(Icons.add_business),
        label: const Text('Nueva empresa'),
      ),
      body: businessesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final message = error is ApiException
              ? error.userMessage
              : 'No se pudieron cargar las empresas.';
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
                    onPressed: () => ref.invalidate(businessesProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (page) {
          if (page.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.store_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('No hay empresas registradas en esta instalación.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _openCreateDialog(context, ref),
                      icon: const Icon(Icons.add_business),
                      label: const Text('Registrar primera empresa'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: page.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final business = page.items[index];
              final isSelected = selectedId == business.id;

              return Card(
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : theme.colorScheme.surfaceContainerLow,
                child: ListTile(
                  leading: Icon(
                    business.isActive ? Icons.store : Icons.store_outlined,
                    color: business.isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(business.name),
                  subtitle: Text(
                    '${business.isActive ? 'Activa' : 'Inactiva'} · ${business.id}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (isSelected)
                        const Chip(
                          label: Text('Seleccionada'),
                          visualDensity: VisualDensity.compact,
                        )
                      else
                        TextButton(
                          onPressed: () {
                            ref
                                .read(selectedBusinessIdProvider.notifier)
                                .select(business.id);
                          },
                          child: const Text('Seleccionar'),
                        ),
                      IconButton(
                        tooltip: 'Editar empresa',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEditDialog(context, ref, business),
                      ),
                    ],
                  ),
                  onTap: () {
                    ref
                        .read(selectedBusinessIdProvider.notifier)
                        .select(business.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BusinessFormDialog extends ConsumerStatefulWidget {
  const _BusinessFormDialog({this.existing});

  final Business? existing;

  @override
  ConsumerState<_BusinessFormDialog> createState() =>
      _BusinessFormDialogState();
}

class _BusinessFormDialogState extends ConsumerState<_BusinessFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late bool _isActive;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _isActive = widget.existing?.isActive ?? true;
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
      final repo = ref.read(adminRepositoryProvider);
      if (widget.existing == null) {
        final created = await repo.createBusiness(
          BusinessCreateRequest(
            name: _nameController.text.trim(),
            isActive: _isActive,
          ),
        );
        ref.read(selectedBusinessIdProvider.notifier).select(created.id);
      } else {
        await repo.updateBusiness(
          widget.existing!.id,
          BusinessUpdateRequest(
            name: _nameController.text.trim(),
            isActive: _isActive,
          ),
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
          _errorMessage = 'No se pudo guardar la empresa.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEdit ? 'Editar empresa' : 'Nueva empresa'),
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
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('business_name_field'),
                controller: _nameController,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la empresa',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Ingresa el nombre de la empresa.';
                  }
                  if (trimmed.length > 160) {
                    return 'Máximo 160 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Empresa activa'),
                subtitle: const Text(
                  'Desactivar conserva los datos y revoca acceso a sus usuarios.',
                ),
                value: _isActive,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _isActive = value),
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
          key: const Key('business_save_button'),
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
