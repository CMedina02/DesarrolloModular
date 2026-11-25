import assert from "node:assert/strict";
import test from "node:test";
import { SignJWT } from "jose";
import { hashPassword, isValidPassword, minimumNewPasswordLength, verifyPassword } from "../src/core/auth/password.js";
import { createAccessTokens } from "../src/core/auth/token.js";
import { readJwtSecret } from "../src/core/config.js";

test("scrypt usa sales independientes y distingue una contraseña incorrecta", async () => {
  const password = "contraseña de ejemplo para pruebas";
  const [first, second] = await Promise.all([hashPassword(password), hashPassword(password)]);
  assert.match(first, /^scrypt-v1\$[a-f0-9]{32}\$[a-f0-9]{128}$/);
  assert.notEqual(first, second);
  assert.equal(await verifyPassword(password, first), true);
  assert.equal(await verifyPassword(password + " ", first), false);
  assert.equal(await verifyPassword(password, "TEST_NOT_A_REAL_HASH"), false);
});

test("la validación de contraseña preserva caracteres Unicode y aplica límites", () => {
  assert.equal(isValidPassword("🔒".repeat(8), minimumNewPasswordLength), true);
  assert.equal(isValidPassword("🔒".repeat(7), minimumNewPasswordLength), false);
  assert.equal(isValidPassword("x".repeat(257)), false);
  assert.equal(isValidPassword("\ud800"), false);
});

test("readJwtSecret exige exactamente 32 bytes codificados en hexadecimal", () => {
  const secretValue = "b7".repeat(32);
  assert.deepEqual(readJwtSecret({ JWT_SECRET: secretValue }), Buffer.alloc(32, 0xb7));
  for (const invalid of [undefined, "a".repeat(63), "z".repeat(64), secretValue + "\n"]) {
    assert.throws(() => readJwtSecret({ JWT_SECRET: invalid }), /JWT_SECRET/);
  }
});

test("JWT valida su firma, el destinatario, el vencimiento y el UUID del usuario", async () => {
  const secret = Buffer.alloc(32, 19);
  const tokens = createAccessTokens(secret);
  const subject = "d08e83a7-04a2-4213-a451-f870431fbd30";
  const goodToken = await tokens.issue(subject);

  assert.equal(await tokens.verify(goodToken), subject);
  assert.equal(await createAccessTokens(Buffer.alloc(32, 20)).verify(goodToken), null);
  assert.equal(await tokens.verify(await tokens.issue("no-es-un-uuid")), null);

  const now = Math.floor(Date.now() / 1000);
  for (const [issuer, audience, expiration] of [
    ["otro-emisor", "desarrollo-modular-api", now + 60],
    ["desarrollo-modular", "otra-api", now + 60],
    ["desarrollo-modular", "desarrollo-modular-api", now - 1],
    ["desarrollo-modular", "desarrollo-modular-api", undefined],
  ]) {
    const token = new SignJWT()
      .setProtectedHeader({ alg: "HS256", typ: "JWT" })
      .setSubject(subject)
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt(now - 120);
    if (expiration !== undefined) {
      token.setExpirationTime(expiration);
    }
    assert.equal(await tokens.verify(await token.sign(secret)), null);
  }
});
