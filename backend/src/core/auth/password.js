import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";

const deriveKey = promisify(scrypt);
const options = { N: 2 ** 15, r: 8, p: 3, maxmem: 64 * 1024 * 1024 };
const hashFormat = /^scrypt-v1\$([0-9a-f]{32})\$([0-9a-f]{128})$/;
const dummySalt = randomBytes(16);
const dummyKey = randomBytes(64);

export function isValidPassword(password, minimumLength = 1) {
  if (typeof password !== "string" || !password.isWellFormed()) {
    return false;
  }

  const length = Array.from(password).length;
  return length >= minimumLength && length <= 256;
}

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await deriveKey(password, salt, 64, options);
  return `scrypt-v1$${salt.toString("hex")}$${key.toString("hex")}`;
}

export async function verifyPassword(password, storedHash) {
  const match = hashFormat.exec(storedHash ?? "");
  const salt = match ? Buffer.from(match[1], "hex") : dummySalt;
  const expectedKey = match ? Buffer.from(match[2], "hex") : dummyKey;
  const actualKey = await deriveKey(password, salt, expectedKey.length, options);
  return timingSafeEqual(actualKey, expectedKey) && match !== null;
}
