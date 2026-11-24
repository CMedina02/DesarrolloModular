import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/enums.dart';

@immutable
class User {
  const User({
    required this.id,
    required this.businessId,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? businessId;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      businessId: json['business_id'] as String?,
      name: json['name'] as String,
      email: json['email'] as String,
      role: UserRole.fromApi(json['role'] as String),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

@immutable
class LoginRequest {
  const LoginRequest({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };

  @override
  String toString() => 'LoginRequest(email: $email, password: [REDACTED])';
}

@immutable
class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final User user;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: (json['expires_in'] as num).toInt(),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  @override
  String toString() =>
      'LoginResponse(tokenType: $tokenType, expiresIn: $expiresIn, '
      'accessToken: [REDACTED], userId: ${user.id})';
}

@immutable
class UserCreateRequest {
  const UserCreateRequest({
    required this.name,
    required this.email,
    required this.role,
    required this.password,
    this.isActive,
  });

  final String name;
  final String email;
  final UserRole role;
  final String password;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'role': role.apiValue,
        'password': password,
        if (isActive != null) 'is_active': isActive,
      };

  @override
  String toString() =>
      'UserCreateRequest(name: $name, email: $email, role: ${role.apiValue}, '
      'password: [REDACTED])';
}

@immutable
class UserUpdateRequest {
  const UserUpdateRequest({
    this.name,
    this.email,
    this.role,
    this.isActive,
  });

  final String? name;
  final String? email;
  final UserRole? role;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (role != null) 'role': role!.apiValue,
        if (isActive != null) 'is_active': isActive,
      };
}
