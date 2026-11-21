import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/enums.dart';
import 'package:inventario_comercial/core/models/user.dart';

enum AuthStatus {
  restoring,
  unauthenticated,
  authenticating,
  authenticated,
}

@immutable
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.expiresAt,
    this.errorMessage,
    this.retryAfterSeconds,
  });

  const AuthState.restoring() : this(status: AuthStatus.restoring);

  const AuthState.authenticating() : this(status: AuthStatus.authenticating);

  const AuthState.unauthenticated({
    String? errorMessage,
    int? retryAfterSeconds,
  }) : this(
          status: AuthStatus.unauthenticated,
          errorMessage: errorMessage,
          retryAfterSeconds: retryAfterSeconds,
        );

  const AuthState.authenticated({
    required User user,
    required DateTime expiresAt,
  }) : this(
          status: AuthStatus.authenticated,
          user: user,
          expiresAt: expiresAt,
        );

  final AuthStatus status;
  final User? user;
  final DateTime? expiresAt;
  final String? errorMessage;
  final int? retryAfterSeconds;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  bool get isLoading =>
      status == AuthStatus.restoring || status == AuthStatus.authenticating;

  UserRole? get role => user?.role;

  /// `business_id` comes strictly from the authenticated profile (`null` for
  /// `PLATFORM_ADMIN`).
  String? get businessId => user?.businessId;

  bool get isPlatformAdmin => role == UserRole.platformAdmin;
  bool get isAdmin => role == UserRole.admin;
  bool get isEmployee => role == UserRole.employee;
}
