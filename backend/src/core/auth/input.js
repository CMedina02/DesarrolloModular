export function normalizeEmail(value) {
  if (typeof value !== "string" || !value.isWellFormed()) {
    return null;
  }

  const email = value.trim();
  if (Array.from(email).length > 255 || !/^[^\s@\p{Cc}]+@[^\s@\p{Cc}]+$/u.test(email)) {
    return null;
  }

  return email;
}
