/// Contract enums aligned with `docs/api/openapi.yaml`.
enum UserRole {
  platformAdmin('PLATFORM_ADMIN'),
  admin('ADMIN'),
  employee('EMPLOYEE');

  const UserRole(this.apiValue);
  final String apiValue;

  static UserRole fromApi(String value) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => throw FormatException('Unknown UserRole: $value'),
    );
  }
}

enum ModuleKey {
  inventory('inventory');

  const ModuleKey(this.apiValue);
  final String apiValue;

  static ModuleKey fromApi(String value) {
    return ModuleKey.values.firstWhere(
      (key) => key.apiValue == value,
      orElse: () => throw FormatException('Unknown ModuleKey: $value'),
    );
  }
}

enum ProductUnit {
  pza('PZA'),
  caja('CAJA'),
  kg('KG'),
  m('M'),
  l('L');

  const ProductUnit(this.apiValue);
  final String apiValue;

  /// Discrete units (`PZA` and `CAJA`) only accept integer quantities.
  bool get requiresIntegerQuantity =>
      this == ProductUnit.pza || this == ProductUnit.caja;

  static ProductUnit fromApi(String value) {
    return ProductUnit.values.firstWhere(
      (unit) => unit.apiValue == value,
      orElse: () => throw FormatException('Unknown ProductUnit: $value'),
    );
  }
}

enum MovementType {
  entry('IN'),
  exit('OUT'),
  adjustment('ADJUSTMENT');

  const MovementType(this.apiValue);
  final String apiValue;

  static MovementType fromApi(String value) {
    return MovementType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException('Unknown MovementType: $value'),
    );
  }
}
