import 'package:flutter/foundation.dart';

/// Response model for `GET /health` (outside `/api/v1`).
@immutable
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.isHealthy,
  });

  final String status;
  final bool isHealthy;

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'unknown').toString();
    return HealthStatus(
      status: rawStatus,
      isHealthy: rawStatus.toLowerCase() == 'ok',
    );
  }
}
