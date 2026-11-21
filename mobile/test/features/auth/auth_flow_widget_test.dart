import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_comercial/app/app.dart';
import 'package:inventario_comercial/core/config/app_config.dart';
import 'package:inventario_comercial/core/config/app_config_provider.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

http.Response _loginSuccessResponse({
  required String role,
  String? businessId,
}) {
  return http.Response(
    jsonEncode({
      'access_token': 'jwt-$role',
      'token_type': 'Bearer',
      'expires_in': 900,
      'user': {
        'id': '44444444-4444-4444-8444-444444444444',
        'business_id': businessId,
        'name': 'Demo $role',
        'email': '${role.toLowerCase()}@demo.local',
        'role': role,
        'is_active': true,
        'created_at': '2026-11-20T18:00:00Z',
        'updated_at': '2026-11-20T18:00:00Z',
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  final testConfig = AppConfig.fromValues(
    rawApiBaseUrl: 'http://127.0.0.1:3000',
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    required http.Client client,
    TokenStorage? storage,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig),
          httpClientProvider.overrideWithValue(client),
          tokenStorageProvider.overrideWithValue(
            storage ?? InMemoryTokenStorage(),
          ),
        ],
        child: const InventarioComercialApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('F03 UI flows: login, role navigation, and logout', () {
    testWidgets('credenciales incorrectas muestran error y conservan el formulario', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Credenciales o sesión no válidas.',
            },
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      await pumpApp(tester, client: client);

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'admin@demo.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'clave-incorrecta',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);
      expect(find.text('Credenciales o sesión no válidas.'), findsOneWidget);
      expect(find.text('admin@demo.local'), findsOneWidget);
      expect(find.text('clave-incorrecta'), findsOneWidget);
    });

    testWidgets('doble toque durante login pendiente genera una sola solicitud', (
      tester,
    ) async {
      var calls = 0;
      final completer = Completer<http.Response>();

      final client = MockClient((request) {
        calls++;
        return completer.future;
      });

      await pumpApp(tester, client: client);

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'admin@demo.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'password-123456789',
      );

      final submitBtn = find.byKey(const Key('login_submit_button'));
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.tap(submitBtn, warnIfMissed: false);
      await tester.pump();

      expect(calls, 1);

      completer.complete(
        _loginSuccessResponse(
          role: 'ADMIN',
          businessId: '22222222-2222-4222-8222-222222222222',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Administración de empresa'), findsOneWidget);
    });

    testWidgets('PLATFORM_ADMIN llega a administración de instalación', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return _loginSuccessResponse(role: 'PLATFORM_ADMIN', businessId: null);
      });

      await pumpApp(tester, client: client);
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'root@demo.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'password-123456789',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Administración de instalación'), findsOneWidget);
      expect(find.text('Empresas'), findsWidgets);
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('Módulos'), findsOneWidget);
      expect(find.text('Historial'), findsNothing);
    });

    testWidgets('EMPLOYEE ve sus funciones y no tiene Historial ni Empleados', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return _loginSuccessResponse(
          role: 'EMPLOYEE',
          businessId: '22222222-2222-4222-8222-222222222222',
        );
      });

      await pumpApp(tester, client: client);
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'emp@demo.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'password-123456789',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Operación de inventario'), findsOneWidget);
      expect(find.text('Catálogo'), findsWidgets);
      expect(find.text('Categorías'), findsOneWidget);
      expect(find.text('Movimientos'), findsOneWidget);
      expect(find.text('Historial'), findsNothing);
      expect(find.text('Empleados'), findsNothing);
      expect(find.text('Empresas'), findsNothing);
    });

    testWidgets('cerrar sesión vuelve al login y bloquea regreso a pantallas privadas', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return _loginSuccessResponse(
          role: 'ADMIN',
          businessId: '22222222-2222-4222-8222-222222222222',
        );
      });

      await pumpApp(tester, client: client);
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'admin@demo.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'password-123456789',
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Administración de empresa'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell_logout_button')));
      await tester.pumpAndSettle();

      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Administración de empresa'), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
      final popped = await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(popped, isFalse);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Administración de empresa'), findsNothing);
    });
  });
}
