import 'package:flutter/foundation.dart';

@immutable
class Category {
  const Category({
    required this.id,
    required this.businessId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String businessId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

@immutable
class CategoryUpsertRequest {
  const CategoryUpsertRequest({required this.name});

  final String name;

  Map<String, dynamic> toJson() => {'name': name};
}
