import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/app/router.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';

/// Initial landing screen for the F01 Flutter foundation.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario Comercial 1.0'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'DesarrolloModular',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Base del cliente Flutter con Riverpod y configuración por entorno.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Entorno activo',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          config.environment,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'URL base de la API',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          config.apiBaseUrl,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.environment);
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Ver configuración de entorno'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
