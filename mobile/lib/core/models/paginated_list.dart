import 'package:flutter/foundation.dart';

/// Generic paginated response matching OpenAPI `*List` schemas.
@immutable
class PaginatedList<T> {
  const PaginatedList({
    required this.items,
    required this.limit,
    required this.offset,
  });

  final List<T> items;
  final int limit;
  final int offset;

  /// Per OpenAPI contract, a page with fewer items than [limit] signals the end.
  bool get hasMore => items.length >= limit;

  factory PaginatedList.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItemJson,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected "items" to be a List');
    }

    return PaginatedList<T>(
      items: rawItems
          .map((item) => fromItemJson(item as Map<String, dynamic>))
          .toList(growable: false),
      limit: (json['limit'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
    );
  }
}
