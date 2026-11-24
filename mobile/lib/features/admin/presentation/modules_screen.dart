import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';

/// Module activation screen for `PLATFORM_ADMIN`.
class ModulesScreen extends ConsumerStatefulWidget {
  const ModulesScreen({super.key});

  @override
  ConsumerState<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends ConsumerState<ModulesScreen> {
  bool _updating = false;
  String? _actionError;

  Future<void> _toggleInventory(String businessId, bool enabled) async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _actionError = null;
    });

    try {
      await ref.read(adminRepositoryProvider).setModuleEnabled(
            businessId,
            moduleKey: ModuleKey.inventory,
            enabled: enabled,
          );
      ref.invalidate(businessModulesProvider(businessId));
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await ref
            .read(authControllerProvider.notifier)
            .handleSessionExpired(message: e.userMessage);
        return;
      }
      if (mounted) {
        setState(() => _actionError = e.userMessage);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'No se pudo actualizar el estado del módulo.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessesAsync = ref.watch(businessesProvider);
    final theme = Theme.of(context);

    return businessesAsync.when(
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
                    : 'No se pudieron cargar las empresas.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(businessesProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Registra una empresa para administrar sus módulos.',
              ),
            ),
          );
        }

        final selectedId = ref.watch(selectedBusinessIdProvider);
        final activeBusinessId = page.items.any((b) => b.id == selectedId)
            ? selectedId!
            : page.items.first.id;
        final modulesAsync =
            ref.watch(businessModulesProvider(activeBusinessId));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              key: const Key('modules_business_selector'),
              initialValue: activeBusinessId,
              decoration: const InputDecoration(
                labelText: 'Empresa seleccionada',
                border: OutlineInputBorder(),
              ),
              items: page.items
                  .map(
                    (b) => DropdownMenuItem<String>(
                      value: b.id,
                      child: Text(
                        '${b.name}${b.isActive ? '' : ' (Inactiva)'}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _actionError = null);
                  ref.read(selectedBusinessIdProvider.notifier).select(value);
                }
              },
            ),
            const SizedBox(height: 16),
            if (_actionError != null) ...[
              Text(
                _actionError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            modulesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        error is ApiException
                            ? error.userMessage
                            : 'No se pudo consultar el estado de módulos.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(
                          businessModulesProvider(activeBusinessId),
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (modules) {
                final inventory = modules
                    .where((m) => m.key == ModuleKey.inventory)
                    .firstOrNull;
                final enabled = inventory?.enabled ?? false;

                return Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: SwitchListTile(
                    key: const Key('inventory_module_switch'),
                    title: const Text('Inventario Comercial 1.0 (inventory)'),
                    subtitle: Text(
                      enabled
                          ? 'Habilitado. Deshabilitar conserva catálogo, existencias e historial.'
                          : 'Deshabilitado por defecto. Habilítalo para permitir el acceso de la empresa.',
                    ),
                    value: enabled,
                    onChanged: _updating
                        ? null
                        : (nextValue) =>
                            _toggleInventory(activeBusinessId, nextValue),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
