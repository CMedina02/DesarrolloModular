import 'package:flutter/foundation.dart';
import 'package:inventario_comercial/core/models/enums.dart';

/// Inventory movement record aligned with OpenAPI `Movement`.
///
/// Quantities (`quantityDelta`, `stockBefore`, `stockAfter`) remain exact
/// decimal strings matching `NUMERIC(14,3)`.
@immutable
class Movement {
  const Movement({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.userId,
    required this.movementType,
    required this.quantityDelta,
    required this.stockBefore,
    required this.stockAfter,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String productId;
  final String userId;
  final MovementType movementType;
  final String quantityDelta;
  final String stockBefore;
  final String stockAfter;
  final String? reason;
  final DateTime createdAt;

  factory Movement.fromJson(Map<String, dynamic> json) {
    return Movement(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      productId: json['product_id'] as String,
      userId: json['user_id'] as String,
      movementType: MovementType.fromApi(json['movement_type'] as String),
      quantityDelta: json['quantity_delta'] as String,
      stockBefore: json['stock_before'] as String,
      stockAfter: json['stock_after'] as String,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

sealed class MovementCreateRequest {
  const MovementCreateRequest();
  Map<String, dynamic> toJson();
}

@immutable
class StockEntryRequest extends MovementCreateRequest {
  const StockEntryRequest({
    required this.productId,
    required this.quantity,
    this.reason,
  });

  final String productId;
  final String quantity;
  final String? reason;

  @override
  Map<String, dynamic> toJson() => {
        'movement_type': MovementType.entry.apiValue,
        'product_id': productId,
        'quantity': quantity,
        if (reason != null && reason!.trim().isNotEmpty) 'reason': reason,
      };
}

@immutable
class StockExitRequest extends MovementCreateRequest {
  const StockExitRequest({
    required this.productId,
    required this.quantity,
    required this.reason,
  });

  final String productId;
  final String quantity;
  final String reason;

  @override
  Map<String, dynamic> toJson() => {
        'movement_type': MovementType.exit.apiValue,
        'product_id': productId,
        'quantity': quantity,
        'reason': reason,
      };
}

@immutable
class StockAdjustmentRequest extends MovementCreateRequest {
  const StockAdjustmentRequest({
    required this.productId,
    required this.countedQuantity,
    required this.reason,
  });

  final String productId;
  final String countedQuantity;
  final String reason;

  @override
  Map<String, dynamic> toJson() => {
        'movement_type': MovementType.adjustment.apiValue,
        'product_id': productId,
        'counted_quantity': countedQuantity,
        'reason': reason,
      };
}
