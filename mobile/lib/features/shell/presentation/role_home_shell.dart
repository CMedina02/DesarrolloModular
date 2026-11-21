import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/shell/presentation/role_navigation.dart';

/// Authenticated shell displaying only the destinations permitted for [user.role].
class RoleHomeShell extends ConsumerStatefulWidget {
  const RoleHomeShell({
    super.key,
    required this.user,
  });

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

  @override
  Widget build(BuildContext context) {
    final destinations = destinationsForRole(widget.user.role);
    final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
    final current = destinations[safeIndex];
    final sectionTitle = sectionTitleForRole(widget.user.role);

    final body = current.id == AppDestinationId.profile
        ? _ProfileView(
            user: widget.user,
            onSignOut: _signOut,
          )
        : _SectionPlaceholderView(
            destination: current,
            user: widget.user,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;

        return Scaffold(
          appBar: AppBar(
            title: Text(sectionTitle),
            actions: [
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
  const _ProfileView({
    required this.user,
    required this.onSignOut,
  });

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
                  Text('Perfil de cuenta', style: theme.textTheme.headlineSmall),
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
  const _InfoRow({
    required this.label,
    required this.value,
  });

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
