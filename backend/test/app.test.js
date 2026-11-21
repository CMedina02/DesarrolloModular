import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";
import { createApp } from "../src/app.js";
import { hashPassword } from "../src/core/auth/password.js";
import { createAccessTokens } from "../src/core/auth/token.js";

async function listen(t, checkDatabase, auth = { users: {}, tokens: {} }) {
  const server = createServer(createApp({ checkDatabase, auth }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");

  t.after(async () => {
    const closed = once(server, "close");
    server.close();
    await closed;
  });

  return `http://127.0.0.1:${server.address().port}`;
}

test("GET /health responde 200 sin consultar PostgreSQL", async (t) => {
  const checkDatabase = t.mock.fn(async () => {
    throw new Error("Base de datos apagada");
  });
  const baseUrl = await listen(t, checkDatabase);
  const response = await fetch(`${baseUrl}/health`);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { status: "ok" });
  assert.equal(checkDatabase.mock.callCount(), 0);
});

test("GET /health/db responde 200 después de comprobar la conexión", async (t) => {
  const checkDatabase = t.mock.fn(async () => {});
  const baseUrl = await listen(t, checkDatabase);
  const response = await fetch(`${baseUrl}/health/db`);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { status: "ok" });
  assert.equal(checkDatabase.mock.callCount(), 1);
});

test("GET /health/db responde 503 sin exponer el error interno", async (t) => {
  const baseUrl = await listen(t, async () => {
    throw new Error("Diagnóstico privado de PostgreSQL");
  });
  const response = await fetch(`${baseUrl}/health/db`);

  assert.equal(response.status, 503);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    error: { code: "DATABASE_UNAVAILABLE", message: "PostgreSQL no está disponible." },
  });
});

test("una ruta desconocida devuelve 404 con el formato JSON de B01", async (t) => {
  const baseUrl = await listen(t, async () => {});
  const response = await fetch(`${baseUrl}/sin-ruta`);

  assert.equal(response.status, 404);
  assert.match(response.headers.get("content-type"), /^application\/json/);
  assert.deepEqual(await response.json(), {
    error: { code: "NOT_FOUND", message: "No se encontró el recurso." },
  });
});

const authPath = "/api/v1/auth";
const userProfile = {
  id: "d08e83a7-04a2-4213-a451-f870431fbd30",
  business_id: null,
  name: "Administrador de prueba",
  email: "admin@example.invalid",
  role: "PLATFORM_ADMIN",
  is_active: true,
  created_at: "2026-11-21T18:00:00.000Z",
  updated_at: "2026-11-21T18:00:00.000Z",
};

function postLogin(baseUrl, rawBody, contentType = "application/json") {
  return fetch(`${baseUrl}${authPath}/login`, {
    method: "POST",
    headers: { "content-type": contentType },
    body: rawBody,
  });
}

test("login emite un JWT, omite el hash y /me vuelve a consultar la sesión", async (t) => {
  const password = " contraseña de ensayo idéntica ";
  const passwordHash = await hashPassword(password);
  const tokens = createAccessTokens(Buffer.alloc(32, 19));
  const users = {
    findByEmail: t.mock.fn(async () => ({ ...userProfile, password_hash: passwordHash })),
    findById: t.mock.fn(async () => userProfile),
  };
  const baseUrl = await listen(t, async () => {}, { users, tokens });
  const login = await postLogin(baseUrl, JSON.stringify({ email: ` ${userProfile.email} `, password }));
  const session = await login.json();

  assert.equal(login.status, 200);
  assert.equal(login.headers.get("cache-control"), "no-store");
  assert.deepEqual({ ...session, access_token: undefined }, {
    access_token: undefined,
    token_type: "Bearer",
    expires_in: 900,
    user: userProfile,
  });
  assert.deepEqual(users.findByEmail.mock.calls[0].arguments, [userProfile.email]);

  const headers = { authorization: `Bearer ${session.access_token}` };
  const me = await fetch(baseUrl + authPath + "/me", { headers });
  assert.equal(me.status, 200);
  assert.deepEqual(await me.json(), userProfile);
  assert.deepEqual(users.findById.mock.calls[0].arguments, [userProfile.id]);

  users.findById.mock.mockImplementation(async () => undefined);
  const revoked = await fetch(baseUrl + authPath + "/me", { headers });
  assert.equal(revoked.status, 401);
  assert.equal(revoked.headers.get("www-authenticate"), "Bearer");
});

test("credenciales incorrectas o cuenta no disponible reciben el mismo 401", async (t) => {
  const passwordHash = await hashPassword("otra contraseña de prueba");
  const users = {
    findByEmail: async (email) => email === userProfile.email ? { ...userProfile, password_hash: passwordHash } : undefined,
  };
  const baseUrl = await listen(t, async () => {}, { users });
  for (const email of [userProfile.email, "ausente@example.invalid"]) {
    const response = await postLogin(baseUrl, JSON.stringify({ email, password: "contraseña incorrecta" }));
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), {
      error: { code: "UNAUTHENTICATED", message: "Credenciales o sesión no válidas." },
    });
  }
});

test("login valida el JSON, el límite de tamaño y el tipo de contenido antes de consultar usuarios", async (t) => {
  const users = { findByEmail: t.mock.fn() };
  const baseUrl = await listen(t, async () => {}, { users });
  for (const [body, status, code, mediaType] of [
    ["{", 400, "VALIDATION_ERROR"],
    ['{"email":"admin@example.invalid","password":"x","extra":true}', 400, "VALIDATION_ERROR"],
    [JSON.stringify({ email: "admin@example.invalid", password: "x".repeat(257) }), 400, "VALIDATION_ERROR"],
    [JSON.stringify({ email: "admin@example.invalid", password: "x".repeat(4400) }), 413, "PAYLOAD_TOO_LARGE"],
    ["sin-json", 415, "UNSUPPORTED_MEDIA_TYPE", "text/plain"],
  ]) {
    const response = await postLogin(baseUrl, body, mediaType);
    assert.equal(response.status, status);
    assert.equal((await response.json()).error.code, code);
  }
  assert.equal(users.findByEmail.mock.callCount(), 0);
});

test("login devuelve 429 con Retry-After al exceder el límite por IP", async (t) => {
  const baseUrl = await listen(t, async () => {}, { users: {} });
  for (let index = 0; index < 10; index++) {
    const response = await postLogin(baseUrl, "{}");
    assert.equal(response.status, 400);
    await response.text();
  }
  const response = await postLogin(baseUrl, "{}");
  assert.equal(response.status, 429);
  assert.match(response.headers.get("retry-after"), /^\d+$/);
  assert.equal((await response.json()).error.code, "TOO_MANY_REQUESTS");
});

test("/me rechaza tokens faltantes o inválidos antes de consultar la sesión", async (t) => {
  const users = { findById: t.mock.fn() };
  const tokens = createAccessTokens(Buffer.alloc(32, 19));
  const baseUrl = await listen(t, async () => {}, { users, tokens });
  for (const headers of [{}, { authorization: "Bearer no-es-token" }]) {
    const response = await fetch(baseUrl + authPath + "/me", { headers });
    assert.equal(response.status, 401);
    assert.equal(response.headers.get("www-authenticate"), "Bearer");
    await response.text();
  }
  assert.equal(users.findById.mock.callCount(), 0);
});
