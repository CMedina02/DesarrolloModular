import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";
import { createApp } from "../src/app.js";
import { hashPassword } from "../src/core/auth/password.js";
import { createAccessTokens } from "../src/core/auth/token.js";

async function listen(t, checkDatabase, auth = { users: {}, tokens: {} }, administration = {}) {
  const server = createServer(createApp({ checkDatabase, auth, ...administration }));
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

const companyId = "be6f55c3-8053-409d-8a40-2bebbc461551";
const otherCompanyId = "2b2c32ce-89bd-4153-b287-299880bb411e";
const employeeId = "f2d8afb5-6f6b-4eb9-b7e7-c590a2bbfbae";
const businessesPath = "/api/v1/businesses";

async function administrationClient(t, role, administration) {
  const profile = {
    ...userProfile,
    role,
    business_id: role === "PLATFORM_ADMIN" ? null : companyId,
  };
  const tokens = createAccessTokens(Buffer.alloc(32, 21));
  const baseUrl = await listen(t, async () => {}, { tokens, users: { findById: async () => profile } }, administration);
  const token = await tokens.issue(profile.id);
  return (path, { method = "GET", body } = {}) => fetch(baseUrl + businessesPath + path, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body !== undefined && { "content-type": "application/json" }),
    },
    body: JSON.stringify(body),
  });
}

test("administración exige sesión y EMPLOYEE recibe 403", async (t) => {
  const baseUrl = await listen(t, async () => {});
  const anonymous = await fetch(baseUrl + businessesPath);
  assert.equal(anonymous.status, 401);
  assert.equal(anonymous.headers.get("www-authenticate"), "Bearer");

  const client = await administrationClient(t, "EMPLOYEE", {});
  for (const path of ["/", `/${companyId}`, `/${companyId}/users`]) {
    const response = await client(path);
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "FORBIDDEN");
  }
});

test("ADMIN solo consulta su empresa y opera cuentas EMPLOYEE", async (t) => {
  const findById = t.mock.fn(async () => ({ id: companyId }));
  const list = t.mock.fn(async () => [{ id: employeeId, role: "EMPLOYEE" }]);
  const update = t.mock.fn(async () => undefined);
  const client = await administrationClient(t, "ADMIN", {
    businesses: { findById },
    businessUsers: { list, update },
  });

  for (const [path, options] of [
    [`/${otherCompanyId}`, {}],
    [`/${otherCompanyId}/users`, {}],
    [`/${otherCompanyId}/users/${employeeId}`, { method: "PATCH", body: { is_active: false } }],
  ]) {
    const response = await client(path, options);
    assert.equal(response.status, 404);
    await response.text();
  }
  assert.equal(findById.mock.callCount(), 0);
  assert.equal(update.mock.callCount(), 0);
  assert.equal((await client(`/${companyId}`, { method: "PATCH", body: { name: "Sin permiso" } })).status, 403);
  assert.equal((await client("/no-es-uuid")).status, 400);

  const own = await client(`/${companyId.toUpperCase()}`);
  assert.equal(own.status, 200);
  assert.deepEqual(await own.json(), { id: companyId });

  const users = await client(`/${companyId}/users?limit=5&offset=2`);
  assert.deepEqual(await users.json(), { items: [{ id: employeeId, role: "EMPLOYEE" }], limit: 5, offset: 2 });
  assert.deepEqual(list.mock.calls[0].arguments, [companyId, false, { limit: 5, offset: 2 }]);

  const rolesPath = `/${companyId}/users/${employeeId}`;
  assert.equal((await client(rolesPath, { method: "PATCH", body: { role: "ADMIN" } })).status, 403);
  assert.equal((await client(rolesPath, { method: "PATCH", body: { is_active: false } })).status, 404);
  assert.equal(update.mock.calls[0].arguments[2], false);

  const createAdmin = await client(`/${companyId}/users`, {
    method: "POST",
    body: { role: "ADMIN", name: "Admin", email: "admin@example.invalid", password: "contraseña de prueba larga" },
  });
  assert.equal(createAdmin.status, 403);
});

test("las empresas validan paginación y cuerpos antes de escribir", async (t) => {
  const create = t.mock.fn(async (input) => ({ id: companyId, name: input.name, is_active: input.isActive }));
  const list = t.mock.fn(async () => []);
  const client = await administrationClient(t, "PLATFORM_ADMIN", { businesses: { create, list } });

  for (const query of ["?limit=101", "?limit=1&limit=2", "?offset=-1", "?offset=9007199254740992"]) {
    assert.equal((await client("/" + query)).status, 400);
  }
  assert.equal(list.mock.callCount(), 0);
  const page = await client("/");
  assert.deepEqual(await page.json(), { items: [], limit: 25, offset: 0 });

  for (const body of [{ name: " " }, { name: "x", is_active: "false" }, { name: "Otra", id: companyId }]) {
    assert.equal((await client("/", { method: "POST", body })).status, 400);
  }
  assert.equal(create.mock.callCount(), 0);

  const response = await client("/", { method: "POST", body: { name: "  Tienda  ", is_active: false } });
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { id: companyId, name: "Tienda", is_active: false });
});

test("las cuentas nuevas guardan un hash y traducen el correo duplicado a 409", async (t) => {
  const create = t.mock.fn(async () => { throw { code: "23505", constraint: "users_email_ci_uniq" }; });
  const client = await administrationClient(t, "PLATFORM_ADMIN", {
    businesses: { findById: async () => ({ id: companyId }) },
    businessUsers: { create },
  });
  const profile = { name: "Persona", email: " persona@example.invalid ", role: "ADMIN" };
  const path = `/${companyId}/users`;
  assert.equal((await client(path, { method: "POST", body: { ...profile, password: "muy-corta" } })).status, 400);
  assert.equal((await client(path, { method: "POST", body: { ...profile, password: "contraseña de prueba larga", business_id: otherCompanyId } })).status, 400);
  assert.equal(create.mock.callCount(), 0);

  const response = await client(path, { method: "POST", body: { ...profile, password: "contraseña de prueba larga" } });
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, "CONFLICT");
  const [id, input] = create.mock.calls[0].arguments;
  assert.equal(id, companyId);
  assert.equal(input.email, "persona@example.invalid");
  assert.match(input.passwordHash, /^scrypt-v1\$/);
  assert(!Object.hasOwn(input, "password"));
});
