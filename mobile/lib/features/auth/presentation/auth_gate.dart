import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/features/auth/application/auth_controller.dart';
import 'package:inventario_comercial/features/auth/application/auth_state.dart';
import 'package:inventario_comercial/features/auth/presentation/login_screen.dart';
import 'package:inventario_comercial/features/shell/presentation/role_home_shell.dart';

/// Root authentication gate.
///
/// Restores any persisted token via `GET /auth/me` on startup and declaratively
/// swaps between [LoginScreen] and [RoleHomeShell] so private screens cannot be
/// reopened with the Back button after logout.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    switch (authState.status) {
      case AuthStatus.restoring:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Validando sesión...'),
              ],
            ),
          ),
        );
      case AuthStatus.authenticated:
        return RoleHomeShell(user: authState.user!);
      case AuthStatus.unauthenticated:
      case AuthStatus.authenticating:
        return const LoginScreen();
    }
  }
}
