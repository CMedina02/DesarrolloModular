const uuidFormat = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

export function isUuid(value) {
  return typeof value === "string" && value.length === 36 && uuidFormat.test(value);
}

export function normalizeName(value, maximumLength) {
  if (typeof value !== "string" || !value.isWellFormed()) {
    return null;
  }

  const name = value.trim();
  return name && !name.includes("\0") && Array.from(name).length <= maximumLength ? name : null;
}
