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
