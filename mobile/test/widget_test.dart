import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_comercial/app/app.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

void main() {
  testWidgets('monta la pantalla inicial de login con configuración por defecto', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
        child: const InventarioComercialApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inventario Comercial 1.0'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('API: http://127.0.0.1:3000'), findsOneWidget);
  });

  testWidgets('refleja una URL base personalizada desde configuración', (
    tester,
  ) async {
    final customConfig = AppConfig.fromValues(
      rawApiBaseUrl: 'http://192.168.1.50:3000/',
      rawEnvironment: 'qa',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(customConfig),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
        child: const InventarioComercialApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DesarrolloModular · qa'), findsOneWidget);
    expect(find.text('API: http://192.168.1.50:3000'), findsOneWidget);
  });

  testWidgets('navega a configuración de entorno desde la pantalla inicial', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
        child: const InventarioComercialApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configuración de entorno'));
    await tester.pumpAndSettle();

    expect(find.text('Configuración de entorno'), findsOneWidget);
    expect(find.text('/api/v1'), findsOneWidget);
    expect(find.text('http://127.0.0.1:3000/api/v1'), findsOneWidget);
  });
}
