import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_comercial/app/app.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';

void main() {
  testWidgets('monta la pantalla inicial con la configuración predeterminada', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InventarioComercialApp(),
      ),
    );

    expect(find.text('Inventario Comercial 1.0'), findsOneWidget);
    expect(find.text('DesarrolloModular'), findsOneWidget);
    expect(find.text('development'), findsOneWidget);
    expect(find.text('http://127.0.0.1:3000'), findsOneWidget);
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
        ],
        child: const InventarioComercialApp(),
      ),
    );

    expect(find.text('qa'), findsOneWidget);
    expect(find.text('http://192.168.1.50:3000'), findsOneWidget);
  });

  testWidgets('navega de la pantalla inicial a configuración de entorno', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InventarioComercialApp(),
      ),
    );

    await tester.tap(find.text('Ver configuración de entorno'));
    await tester.pumpAndSettle();

    expect(find.text('Configuración de entorno'), findsOneWidget);
    expect(find.text('/api/v1'), findsOneWidget);
    expect(find.text('http://127.0.0.1:3000/api/v1'), findsOneWidget);
  });
}
