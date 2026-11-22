import 'package:inventario_comercial/core/models/enums.dart';

/// OpenAPI-aligned decimal string validators for prices and quantities.
abstract final class ProductValidators {
  static final RegExp _priceRegex =
      RegExp(r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$');
  static final RegExp _quantityRegex =
      RegExp(r'^(0|[1-9][0-9]{0,10})(\.[0-9]{1,3})?$');
  static final RegExp _zeroQuantityRegex = RegExp(r'^0(\.0{1,3})?$');
  static final RegExp _integerQuantityRegex =
      RegExp(r'^(0|[1-9][0-9]{0,10})(\.0{1,3})?$');

  static String? validatePrice(String? raw, {bool requiredField = false}) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return requiredField ? 'Ingresa un precio válido.' : null;
    }
    if (!_priceRegex.hasMatch(value)) {
      return 'Usa un decimal no negativo con hasta 2 decimales (ej. 19.90).';
    }
    return null;
  }

  static String? validateQuantity(
    String? raw, {
    required ProductUnit unit,
    bool allowZero = true,
    bool requiredField = false,
  }) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return requiredField ? 'Ingresa una cantidad válida.' : null;
    }
    if (!_quantityRegex.hasMatch(value)) {
      return 'Usa un decimal no negativo con hasta 3 decimales (ej. 2.500).';
    }
    if (!allowZero && _zeroQuantityRegex.hasMatch(value)) {
      return 'La cantidad debe ser mayor que cero.';
    }
    if (unit.requiresIntegerQuantity && !_integerQuantityRegex.hasMatch(value)) {
      return 'La unidad ${unit.apiValue} solo admite cantidades enteras.';
    }
    return null;
  }
}
