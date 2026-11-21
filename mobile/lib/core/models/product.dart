import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/enums.dart';

/// Product model aligned with OpenAPI `Product`.
///
/// Prices (`costPrice`, `salePrice`) and quantities (`minStock`,
/// `stockQuantity`) are preserved as exact decimal strings to avoid
/// floating-point precision loss.
@immutable
class Product {
  const Product({
    required this.id,
    required this.businessId,
    required this.categoryId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.costPrice,
    required this.salePrice,
    required this.minStock,
    required this.isActive,
    required this.stockQuantity,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String businessId;
  final String categoryId;
  final String sku;
  final String name;
  final ProductUnit unit;
  final String costPrice;
  final String salePrice;
  final String minStock;
  final bool isActive;
  final String stockQuantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      categoryId: json['category_id'] as String,
      sku: json['sku'] as String,
      name: json['name'] as String,
      unit: ProductUnit.fromApi(json['unit'] as String),
      costPrice: json['cost_price'] as String,
      salePrice: json['sale_price'] as String,
      minStock: json['min_stock'] as String,
      isActive: json['is_active'] as bool,
      stockQuantity: json['stock_quantity'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

@immutable
class ProductCreateRequest {
  const ProductCreateRequest({
    required this.categoryId,
    required this.sku,
    required this.name,
    required this.unit,
    this.costPrice,
    this.salePrice,
    this.minStock,
    this.isActive,
  });

  final String categoryId;
  final String sku;
  final String name;
  final ProductUnit unit;
  final String? costPrice;
  final String? salePrice;
  final String? minStock;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'sku': sku,
        'name': name,
        'unit': unit.apiValue,
        if (costPrice != null) 'cost_price': costPrice,
        if (salePrice != null) 'sale_price': salePrice,
        if (minStock != null) 'min_stock': minStock,
        if (isActive != null) 'is_active': isActive,
      };
}

@immutable
class ProductUpdateRequest {
  const ProductUpdateRequest({
    this.categoryId,
    this.sku,
    this.name,
    this.unit,
    this.costPrice,
    this.salePrice,
    this.minStock,
    this.isActive,
  });

  final String? categoryId;
  final String? sku;
  final String? name;
  final ProductUnit? unit;
  final String? costPrice;
  final String? salePrice;
  final String? minStock;
  final bool? isActive;

  Map<String, dynamic> toJson() => {
        if (categoryId != null) 'category_id': categoryId,
        if (sku != null) 'sku': sku,
        if (name != null) 'name': name,
        if (unit != null) 'unit': unit!.apiValue,
        if (costPrice != null) 'cost_price': costPrice,
        if (salePrice != null) 'sale_price': salePrice,
        if (minStock != null) 'min_stock': minStock,
        if (isActive != null) 'is_active': isActive,
      };
}
