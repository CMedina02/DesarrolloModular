import 'package:inventario_comercial/core/models/user.dart';
import 'package:inventario_comercial/core/network/api_client.dart';

/// Auth endpoints (`POST /auth/login` and `GET /auth/me`).
class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Authenticates with email and password.
  ///
  /// Trims outer spaces from [email] and preserves [password] untouched per
  /// the OpenAPI contract.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final request = LoginRequest(
      email: email.trim(),
      password: password,
    );
    final json = await _apiClient.postJson(
      '/auth/login',
      body: request.toJson(),
      authenticated: false,
    );
    return LoginResponse.fromJson(json);
  }

  /// Validates the active JWT and retrieves the current user profile.
  Future<User> getMe() async {
    final json = await _apiClient.getJson(
      '/auth/me',
      authenticated: true,
    );
    return User.fromJson(json);
  }
}
