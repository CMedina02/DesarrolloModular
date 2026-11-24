import { fitsUnit, formatQuantityMillis, maximumQuantityMillis, quantityToMillis } from "../quantity.js";

export class StockError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function calculateStock(product, movement) {
  if (!product.is_active) {
    throw new StockError(409, "CONFLICT", "El producto está inactivo.");
  }

  if (!fitsUnit(product.unit, movement.quantity)) {
    throw new StockError(400, "VALIDATION_ERROR", "Piezas y cajas requieren cantidades enteras.");
  }

  const before = quantityToMillis(product.stock_quantity);
  const quantity = quantityToMillis(movement.quantity);
  const after = movement.type === "ADJUSTMENT"
    ? quantity
    : before + (movement.type === "OUT" ? -quantity : quantity);

  if (after < 0n) {
    throw new StockError(409, "CONFLICT", "Stock insuficiente para la salida.");
  }
  if (after > maximumQuantityMillis) {
    throw new StockError(409, "CONFLICT", "La existencia supera el máximo permitido.");
  }
  if (after === before) {
    throw new StockError(409, "CONFLICT", "El conteo coincide con la existencia actual.");
  }

  return {
    before: formatQuantityMillis(before),
    after: formatQuantityMillis(after),
    delta: formatQuantityMillis(after - before),
  };
}
