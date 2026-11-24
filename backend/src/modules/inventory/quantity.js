const quantityFormat = /^(0|[1-9][0-9]{0,10})(\.[0-9]{1,3})?$/;

export const maximumQuantityMillis = 10n ** 14n - 1n;

export function normalizeQuantity(value) {
  return typeof value === "string" && value === value.trim() && quantityFormat.test(value) ? value : null;
}

export function fitsUnit(unit, quantity) {
  return (unit !== "PZA" && unit !== "CAJA") || /^\d+(\.0+)?$/.test(quantity);
}

export function quantityToMillis(quantity) {
  const [whole, fraction = ""] = quantity.split(".");
  return BigInt(whole + fraction.padEnd(3, "0"));
}

export function formatQuantityMillis(millis) {
  const digits = (millis < 0n ? -millis : millis).toString().padStart(4, "0");
  const sign = millis < 0n ? "-" : "";
  return `${sign}${digits.slice(0, -3)}.${digits.slice(-3)}`;
}
