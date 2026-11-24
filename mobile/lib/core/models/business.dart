import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/enums.dart';

@immutable
class Business {
  const Business({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

@immutable
class BusinessCreateRequest {
  const BusinessCreateRequest({
    required this.name,
    this.isActive,
  });

  final String name;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (isActive != null) 'is_active': isActive,
      };
}

@immutable
class BusinessUpdateRequest {
  const BusinessUpdateRequest({
    this.name,
    this.isActive,
  });

  final String? name;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (isActive != null) 'is_active': isActive,
      };
}

@immutable
class BusinessModule {
  const BusinessModule({
    required this.key,
    required this.enabled,
  });

  final ModuleKey key;
  final bool enabled;

  factory BusinessModule.fromJson(Map<String, dynamic> json) {
    return BusinessModule(
      key: ModuleKey.fromApi(json['key'] as String),
      enabled: json['enabled'] as bool,
    );
  }
}

@immutable
class ModuleStateRequest {
  const ModuleStateRequest({required this.enabled});

  final bool enabled;

  Map<String, dynamic> toJson() => {'enabled': enabled};
}
