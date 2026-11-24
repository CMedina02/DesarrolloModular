import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/network/api_client_provider.dart';
import 'package:inventario_comercial/core/network/api_exception.dart';
import 'package:inventario_comercial/features/auth/application/auth_state.dart';
import 'package:inventario_comercial/features/auth/data/auth_repository.dart';
import 'package:inventario_comercial/features/auth/data/token_storage.dart';

typedef Clock = DateTime Function();

/// Injectable clock for deterministic JWT expiration testing (900 s).
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// Secure token persistence provider (overridden in tests).
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

/// Auth repository wired to [apiClientProvider].
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

/// Manages login, `/auth/me` restoration, 900 s JWT expiration, and logout.
class AuthController extends Notifier<AuthState> {
  static const int defaultJwtTtlSeconds = 900;

  Timer? _expiryTimer;
  bool _restoreStarted = false;

  @override
  AuthState build() {
    ref.onDispose(_cancelExpiryTimer);
    return const AuthState.restoring();
  }

  /// Checks secure storage for a saved token and validates it via `GET /auth/me`.
  Future<void> restoreSession() async {
    if (_restoreStarted) return;
    _restoreStarted = true;

    state = const AuthState.restoring();

    final storage = ref.read(tokenStorageProvider);
    final token = await storage.readToken();
    if (token == null || token.isEmpty) {
      ref.read(authTokenProvider.notifier).clear();
      state = const AuthState.unauthenticated();
      return;
    }

    ref.read(authTokenProvider.notifier).setToken(token);

    try {
      final user = await ref.read(authRepositoryProvider).getMe();
      final expiresAt = ref
          .read(clockProvider)()
          .add(const Duration(seconds: defaultJwtTtlSeconds));
      _scheduleExpiration(const Duration(seconds: defaultJwtTtlSeconds));
      state = AuthState.authenticated(user: user, expiresAt: expiresAt);
    } on ApiException catch (e) {
      await _clearSessionState();
      final message = e.isAuthFailure
          ? 'Tu sesión expiró o dejó de ser válida. Inicia sesión nuevamente.'
          : e.userMessage;
      state = AuthState.unauthenticated(
        errorMessage: message,
        retryAfterSeconds: e.retryAfterSeconds,
      );
    } catch (_) {
      await _clearSessionState();
      state = const AuthState.unauthenticated(
        errorMessage: 'No se pudo validar tu sesión. Inicia sesión nuevamente.',
      );
    }
  }

  /// Signs in via `POST /auth/login`. Prevents duplicate concurrent submissions.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    if (state.status == AuthStatus.authenticating) {
      return false;
    }

    _cancelExpiryTimer();
    state = const AuthState.authenticating();

    try {
      final response = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
          );

      await ref.read(tokenStorageProvider).writeToken(response.accessToken);
      ref.read(authTokenProvider.notifier).setToken(response.accessToken);

      final ttl = response.expiresIn > 0
          ? response.expiresIn
          : defaultJwtTtlSeconds;
      final expiresAt =
          ref.read(clockProvider)().add(Duration(seconds: ttl));
      _scheduleExpiration(Duration(seconds: ttl));

      state = AuthState.authenticated(
        user: response.user,
        expiresAt: expiresAt,
      );
      return true;
    } on ApiException catch (e) {
      ref.read(authTokenProvider.notifier).clear();
      state = AuthState.unauthenticated(
        errorMessage: e.userMessage,
        retryAfterSeconds: e.retryAfterSeconds,
      );
      return false;
    } catch (_) {
      ref.read(authTokenProvider.notifier).clear();
      state = const AuthState.unauthenticated(
        errorMessage: 'No se pudo iniciar sesión. Inténtalo de nuevo.',
      );
      return false;
    }
  }

  /// Verifies against the injected clock whether the current JWT has expired.
  Future<bool> checkExpiration() async {
    final expiresAt = state.expiresAt;
    if (!state.isAuthenticated || expiresAt == null) {
      return false;
    }
    final now = ref.read(clockProvider)();
    if (!now.isBefore(expiresAt)) {
      await handleSessionExpired();
      return true;
    }
    return false;
  }

  /// Clears credentials and forces return to login after a 401 or timeout.
  Future<void> handleSessionExpired({String? message}) async {
    await _clearSessionState();
    state = AuthState.unauthenticated(
      errorMessage: message ??
          'Tu sesión venció (vigencia de 900 s). Inicia sesión nuevamente.',
    );
  }

  /// Clears local token, profile, and expiry timer on user-initiated sign out.
  Future<void> logout() async {
    await _clearSessionState();
    state = const AuthState.unauthenticated();
  }

  Future<void> _clearSessionState() async {
    _cancelExpiryTimer();
    ref.read(authTokenProvider.notifier).clear();
    await ref.read(tokenStorageProvider).deleteToken();
  }

  void _scheduleExpiration(Duration duration) {
    _cancelExpiryTimer();
    _expiryTimer = Timer(duration, () {
      handleSessionExpired();
    });
  }

  void _cancelExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
