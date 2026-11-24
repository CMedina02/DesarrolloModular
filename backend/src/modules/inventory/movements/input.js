import { isUuid } from "../../../core/validation.js";
import { normalizeQuantity, quantityToMillis } from "../quantity.js";

const movementTypes = ["IN", "OUT", "ADJUSTMENT"];
const entryFields = ["product_id", "movement_type", "quantity", "reason"];
const adjustmentFields = ["product_id", "movement_type", "counted_quantity", "reason"];

export function movementInput(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return null;
  }

  const { product_id: productId, movement_type: type, reason } = body;
  if (!isUuid(productId) || !movementTypes.includes(type)) {
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

const timestampPattern = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/i;

function normalizeTimestamp(value) {
  if (typeof value !== "string" || value !== value.trim()) {
    return null;
  }
  const match = timestampPattern.exec(value);
  if (!match) {
    return null;
  }

  const [, date, time, fraction = "", zone] = match;
  const local = `${date}T${time}`;
  const milliseconds = Date.parse(`${local}Z`);
  if (!Number.isFinite(milliseconds) || new Date(milliseconds).toISOString().slice(0, 19) !== local ||
      date.startsWith("0000-")) {
    return null;
  }

  let offset = 0;
  if (zone.toUpperCase() !== "Z") {
    const hours = Number(zone.slice(1, 3));
    const minutes = Number(zone.slice(4, 6));
    if (hours > 23 || minutes > 59) {
      return null;
    }
    offset = (zone[0] === "-" ? -1 : 1) * (hours * 60 + minutes);
  }

  const utc = new Date(milliseconds - offset * 60_000);
  if (utc.getUTCFullYear() < 1 || utc.getUTCFullYear() > 9999) {
    return null;
  }

  return `${utc.toISOString().slice(0, 19)}.${fraction.padEnd(6, "0")}Z`;
}

export function movementFilters(query) {
  const { product_id: productId, movement_type: type, from: rawFrom, to: rawTo } = query;
  if ((productId !== undefined && !isUuid(productId)) ||
      (type !== undefined && !movementTypes.includes(type))) {
    return null;
  }

  const from = rawFrom === undefined ? undefined : normalizeTimestamp(rawFrom);
  const to = rawTo === undefined ? undefined : normalizeTimestamp(rawTo);
  if (from === null || to === null || (from && to && from >= to)) {
    return null;
  }

  return { productId, type, from, to };
}
