import { normalizeEmail } from "../auth/input.js";
import { isValidPassword, minimumNewPasswordLength } from "../auth/password.js";
import { normalizeName } from "../validation.js";

const businessFields = ["name", "is_active"];
const userFields = ["name", "email", "role", "is_active"];
const userCreateFields = [...userFields, "password"];

function hasAllowedFields(body, allowed) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return false;
  }

  const keys = Object.keys(body);
  return keys.length > 0 && keys.every((key) => allowed.includes(key));
}

export function businessInput(body, creating) {
  if (!hasAllowedFields(body, businessFields)) {
    return null;
  }

  const { name: rawName, is_active: isActive } = body;
  const name = normalizeName(rawName, 160);
  if (((creating || rawName !== undefined) && !name) ||
      (isActive !== undefined && typeof isActive !== "boolean")) {
    return null;
  }

  return { name, isActive };
}

export function userInput(body, creating) {
  if (!hasAllowedFields(body, creating ? userCreateFields : userFields)) {
    return null;
  }

  const { name: rawName, email: rawEmail, role, password, is_active: isActive } = body;
  const name = normalizeName(rawName, 150);
  const email = normalizeEmail(rawEmail);
  if (((creating || rawName !== undefined) && !name) ||
      ((creating || rawEmail !== undefined) && !email) ||
      ((creating || role !== undefined) && !["ADMIN", "EMPLOYEE"].includes(role)) ||
      (creating && !isValidPassword(password, minimumNewPasswordLength)) ||
      (isActive !== undefined && typeof isActive !== "boolean")) {
    return null;
  }

  return { name, email, role, password, isActive };
}

function pageInteger(value, defaultValue, minimum, maximum) {
  if (value === undefined) {
    return defaultValue;
  }
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    return null;
  }

  const number = Number(value);
  return Number.isSafeInteger(number) && number >= minimum && number <= maximum ? number : null;
}

export function pagination(query) {
  const limit = pageInteger(query.limit, 25, 1, 100);
  const offset = pageInteger(query.offset, 0, 0, Number.MAX_SAFE_INTEGER);
  return limit === null || offset === null ? null : { limit, offset };
}
