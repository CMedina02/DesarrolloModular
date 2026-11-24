import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_comercial/core/config/app_config.dart';

/// Root provider exposing the active public client configuration.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});
