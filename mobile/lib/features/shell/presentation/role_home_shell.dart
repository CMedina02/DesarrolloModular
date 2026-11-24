import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/admin/application/admin_providers.dart';
import 'package:inventario_comercial/features/admin/presentation/businesses_screen.dart';
import 'package:inventario_comercial/features/admin/presentation/modules_screen.dart';
import 'package:inventario_comercial/features/admin/presentation/users_screen.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/shell/presentation/role_navigation.dart';

/// Authenticated shell displaying only the destinations permitted for [user.role].
class RoleHomeShell extends ConsumerStatefulWidget {
  const RoleHomeShell({super.key, required this.user});

  final User user;

  @override
  ConsumerState<RoleHomeShell> createState() => _RoleHomeShellState();
}

class _RoleHomeShellState extends ConsumerState<RoleHomeShell> {
  int _selectedIndex = 0;

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await ref.read(authControllerProvider.notifier).logout();
    navigator.popUntil((route) => route.isFirst);
  }

  bool _isInventoryDestination(AppDestinationId id) {
    return id == AppDestinationId.products ||
        id == AppDestinationId.categories ||
        id == AppDestinationId.movements ||
        id == AppDestinationId.history;
  }

  Widget _buildBody(AppDestination current) {
    switch (current.id) {
      case AppDestinationId.businesses:
        return const BusinessesScreen();
      case AppDestinationId.users:
      case AppDestinationId.employees:
        return UsersScreen(currentUser: widget.user);
      case AppDestinationId.modules:
        return const ModulesScreen();
      case AppDestinationId.profile:
        return _ProfileView(user: widget.user, onSignOut: _signOut);
      case AppDestinationId.products:
      case AppDestinationId.categories:
      case AppDestinationId.movements:
      case AppDestinationId.history:
        final businessId = widget.user.businessId;
        if (businessId == null) {
          return const Center(
            child: Text('Tu cuenta no tiene una empresa asociada.'),
          );
        }
        return _InventoryModuleGate(
          businessId: businessId,
          child: _SectionPlaceholderView(
            destination: current,
            user: widget.user,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = destinationsForRole(widget.user.role);
    final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
    final current = destinations[safeIndex];
    final sectionTitle = sectionTitleForRole(widget.user.role);

    final businessId = widget.user.businessId;
    final inventoryStatusAsync = businessId != null
        ? ref.watch(isInventoryEnabledProvider(businessId))
        : null;

    final body = _buildBody(current);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;

        return Scaffold(
          appBar: AppBar(
            title: Text(sectionTitle),
            actions: [
              if (inventoryStatusAsync != null &&
                  _isInventoryDestination(current.id))
                inventoryStatusAsync.maybeWhen(
                  data: (enabled) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      key: const Key('inventory_status_chip'),
                      label: Text(
                        enabled
                            ? 'Inventario: Activo'
                            : 'Inventario: Deshabilitado',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text(widget.user.role.apiValue),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              IconButton(
                key: const Key('shell_logout_button'),
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
              ),
            ],
          ),
          body: useRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: safeIndex,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (index) {
                        setState(() => _selectedIndex = index);
                      },
                      destinations: destinations
                          .map(
                            (d) => NavigationRailDestination(
                              icon: Icon(d.icon),
                              label: Text(d.label),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  destinations: destinations
                      .map(
                        (d) => NavigationDestination(
                          icon: Icon(d.icon),
                          label: d.label,
                        ),
                      )
                      .toList(growable: false),
                ),
        );
      },
    );
  }
}

class _InventoryModuleGate extends ConsumerWidget {
  const _InventoryModuleGate({required this.businessId, required this.child});

  final String businessId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(isInventoryEnabledProvider(businessId));
    final theme = Theme.of(context);

    return enabledAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Consultando módulos de la empresa...'),
          ],
        ),
      ),
      error: (error, _) {
        final message = error is ApiException
            ? error.userMessage
            : 'No se pudo consultar el estado del módulo Inventario.';
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
                  onPressed: () =>
                      ref.invalidate(businessModulesProvider(businessId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        );
      },
      data: (enabled) {
        if (!enabled) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  key: const Key('inventory_disabled_banner'),
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 48,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Módulo Inventario deshabilitado',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'El módulo de Inventario no está habilitado para tu empresa. '
                          'Solicita a un PLATFORM_ADMIN que lo active. Tus datos se conservan.',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => ref.invalidate(
                            businessModulesProvider(businessId),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizar estado'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return child;
      },
    );
  }
}

class _SectionPlaceholderView extends StatelessWidget {
  const _SectionPlaceholderView({
    required this.destination,
    required this.user,
  });

  final AppDestination destination;
  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        destination.icon,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination.label,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    destination.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Sesión activa: ${user.name} (${user.email})',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.businessId != null
                        ? 'Empresa (business_id): ${user.businessId}'
                        : 'Ámbito: Instalación global (PLATFORM_ADMIN)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.user, required this.onSignOut});

  final User user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Perfil de cuenta',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(label: 'Nombre', value: user.name),
                  _InfoRow(label: 'Correo', value: user.email),
                  _InfoRow(label: 'Rol', value: user.role.apiValue),
                  _InfoRow(
                    label: 'Empresa (business_id)',
                    value: user.businessId ?? 'Instalación global (null)',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    key: const Key('profile_logout_button'),
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
