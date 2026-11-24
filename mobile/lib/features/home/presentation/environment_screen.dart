import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';

/// Displays the active public client configuration.
class EnvironmentScreen extends ConsumerWidget {
  const EnvironmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de entorno'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ConfigTile(
                label: 'Entorno (APP_ENV)',
                value: config.environment,
              ),
              const SizedBox(height: 12),
              _ConfigTile(
                label: 'URL base (API_BASE_URL)',
                value: config.apiBaseUrl,
              ),
              const SizedBox(height: 12),
              const _ConfigTile(
                label: 'Prefijo de API',
                value: AppConfig.apiPrefix,
              ),
              const SizedBox(height: 12),
              _ConfigTile(
                label: 'Base completa de endpoints',
                value: config.apiBaseWithPrefix,
              ),
              const SizedBox(height: 24),
              Text(
                'La URL base se configura al ejecutar la app con '
                '--dart-define=API_BASE_URL=<url> sin modificar el código fuente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
