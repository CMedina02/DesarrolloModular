import { isUuid } from "../../../core/validation.js";
import { normalizeQuantity, quantityToMillis } from "../quantity.js";

const entryFields = ["product_id", "movement_type", "quantity", "reason"];
const adjustmentFields = ["product_id", "movement_type", "counted_quantity", "reason"];

export function movementInput(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return null;
  }

  const { product_id: productId, movement_type: type, reason } = body;
  if (!isUuid(productId) || !["IN", "OUT", "ADJUSTMENT"].includes(type)) {
    return null;
  }

  const adjustment = type === "ADJUSTMENT";
  const fields = adjustment ? adjustmentFields : entryFields;
  const quantity = normalizeQuantity(adjustment ? body.counted_quantity : body.quantity);
  if (!quantity || (!adjustment && quantityToMillis(quantity) === 0n) ||
      !Object.keys(body).every((key) => fields.includes(key))) {
    return null;
  }

  if (type === "IN" && reason === undefined) {
    return { productId, type, quantity, reason: null };
  }

  if (typeof reason !== "string" || !reason.isWellFormed() || !reason.trim() || reason.includes("\0")) {
    return null;
  }

  return { productId, type, quantity, reason: reason.trim() };
}
