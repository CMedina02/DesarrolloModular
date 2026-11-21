import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over platform-secure token persistence.
abstract class TokenStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

/// Uses `flutter_secure_storage` (Keystore on Android, Credential Manager on
/// Windows, Web Crypto on Web).
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'dm_access_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() async {
    try {
      final value = await _storage.read(key: _tokenKey);
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Ignore storage cleanup errors on logout.
    }
  }
}

/// Deterministic in-memory storage used in automated tests.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage({String? initialToken}) : _token = initialToken;

  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }
}
