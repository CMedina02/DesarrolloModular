import { isUuid, normalizeName } from "../../../core/validation.js";
import { normalizeQuantity } from "../quantity.js";

const units = ["PZA", "CAJA", "KG", "M", "L"];
const required = ["category_id", "sku", "name", "unit"];
const priceFormat = /^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$/;

function decimal(value, format) {
  return typeof value === "string" && value === value.trim() && format.test(value) ? value : null;
}

const validators = {
  category_id: (value) => isUuid(value) ? value : null,
  sku: (value) => normalizeName(value, 60),
  name: (value) => normalizeName(value, 180),
  unit: (value) => units.includes(value) ? value : null,
  cost_price: (value) => decimal(value, priceFormat),
  sale_price: (value) => decimal(value, priceFormat),
  min_stock: normalizeQuantity,
  is_active: (value) => typeof value === "boolean" ? value : null,
};

export function productInput(body, creating) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return null;
  }

  const entries = Object.entries(body);
  if (entries.length === 0 || (creating && !required.every((field) => Object.hasOwn(body, field)))) {
    return null;
  }

  const product = {};
  for (const [name, value] of entries) {
    if (!Object.hasOwn(validators, name)) {
      return null;
    }

    const validated = validators[name](value);
    if (validated === null) {
      return null;
    }
    product[name] = validated;
  }

  return product;
}

function queryBoolean(value) {
  if (value === undefined) return undefined;
  if (value === "true") return true;
  if (value === "false") return false;
  return null;
}

export function productFilters(query) {
  const { category_id: categoryId } = query;
  const isActive = queryBoolean(query.is_active);
  const lowStock = queryBoolean(query.low_stock);
  if ((categoryId !== undefined && !isUuid(categoryId)) || isActive === null || lowStock === null) {
    return null;
  }

  return { categoryId, isActive, lowStock: lowStock ?? false };
}
