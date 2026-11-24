import 'package:flutter/material.dart';
import 'package:inventario_comercial/features/auth/presentation/auth_gate.dart';
import 'package:inventario_comercial/features/home/presentation/environment_screen.dart';

/// Route names for application navigation.
abstract final class AppRoutes {
  static const String home = '/';
  static const String environment = '/environment';
}

/// Central route generator for the application.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.environment:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const EnvironmentScreen(),
        );
      case AppRoutes.home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AuthGate(),
        );
    }
  }
}
