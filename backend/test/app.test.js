import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

test("el modo web sirve Flutter y reserva las rutas de la API", async (t) => {
  const webDirectory = await mkdtemp(join(tmpdir(), "desarrollo-web-test-"));
  t.after(() => rm(webDirectory, { recursive: true, force: true }));
  const apiDirectory = join(webDirectory, "api", "v1");
  await mkdir(apiDirectory, { recursive: true });
  await Promise.all([
    writeFile(join(webDirectory, "index.html"), "<!doctype html><title>Inventario</title>"),
    writeFile(join(webDirectory, "engine.wasm"), Buffer.from([0, 97, 115, 109])),
    writeFile(join(apiDirectory, "unknown"), "archivo estático"),
  ]);

  const baseUrl = await listen(t, async () => {}, undefined, { webDirectory });
  const index = await fetch(baseUrl);
  assert.equal(index.status, 200);
  assert.match(index.headers.get("content-type"), /^text\/html/);
  assert.match(await index.text(), /<title>Inventario<\/title>/);

  const engine = await fetch(`${baseUrl}/engine.wasm`);
  assert.equal(engine.status, 200);
  assert.equal(engine.headers.get("content-type"), "application/wasm");
  assert.equal(engine.headers.get("x-content-type-options"), "nosniff");
  await engine.arrayBuffer();

  const health = await fetch(`${baseUrl}/health/db`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: "ok" });

  const unknown = await fetch(`${baseUrl}/api/v1/unknown`);
  assert.equal(unknown.status, 404);
  assert.equal((await unknown.json()).error.code, "NOT_FOUND");
});

test("el modo API responde 404 en la raíz", async (t) => {
  const baseUrl = await listen(t, async () => {});
  const response = await fetch(baseUrl);
  assert.equal(response.status, 404);
  assert.equal((await response.json()).error.code, "NOT_FOUND");
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
const writeClient = {};

async function administrationClient(t, role, administration) {
  const profile = {
    ...userProfile,
    role,
    business_id: role === "PLATFORM_ADMIN" ? null : companyId,
  };
  const tokens = createAccessTokens(Buffer.alloc(32, 21));
  const authorizedWrite = async (_session, operation) => ({
    status: "authorized",
    resource: await operation(writeClient),
  });
  const baseUrl = await listen(t, async () => {}, { tokens, users: { findById: async () => profile } }, {
    authorizedWrite,
    ...administration,
  });
  const token = await tokens.issue(profile.id);
  return (path, { method = "GET", body, extraHeaders } = {}) => fetch(baseUrl + businessesPath + path, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body !== undefined && { "content-type": "application/json" }),
      ...extraHeaders,
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
  assert.equal(update.mock.calls[0].arguments[0], writeClient);
  assert.equal(update.mock.calls[0].arguments[3], false);

  const createAdmin = await client(`/${companyId}/users`, {
    method: "POST",
    body: { role: "ADMIN", name: "Admin", email: "admin@example.invalid", password: "contraseña de prueba larga" },
  });
  assert.equal(createAdmin.status, 403);
});

test("las empresas validan paginación y cuerpos antes de escribir", async (t) => {
  const create = t.mock.fn(async (_client, input) => ({ id: companyId, name: input.name, is_active: input.isActive }));
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
  assert.equal((await client(path, { method: "POST", body: { ...profile, password: "x".repeat(7) } })).status, 400);
  assert.equal((await client(path, { method: "POST", body: { ...profile, password: "contraseña de prueba larga", business_id: otherCompanyId } })).status, 400);
  assert.equal(create.mock.callCount(), 0);

  const response = await client(path, { method: "POST", body: { ...profile, password: "x".repeat(8) } });
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, "CONFLICT");
  const [clientUsed, id, input] = create.mock.calls[0].arguments;
  assert.equal(clientUsed, writeClient);
  assert.equal(id, companyId);
  assert.equal(input.email, "persona@example.invalid");
  assert.match(input.passwordHash, /^scrypt-v1\$/);
  assert(!Object.hasOwn(input, "password"));
});

test("el ámbito de empresa solo se deriva de la sesión y la ruta", async (t) => {
  const findById = t.mock.fn(async (id) => ({ id }));
  const list = t.mock.fn(async () => []);
  const client = await administrationClient(t, "ADMIN", {
    businesses: { findById },
    businessUsers: { list },
  });
  const headers = { "x-business-id": otherCompanyId, "x-role": "PLATFORM_ADMIN" };
  const allowed = await client(`/${companyId.toUpperCase()}/users?business_id=${otherCompanyId}`, {
    extraHeaders: headers,
  });
  assert.equal(allowed.status, 200);
  assert.equal(allowed.headers.get("cache-control"), "no-store");
  assert.equal(findById.mock.calls[0].arguments[0], companyId);
  assert.equal(list.mock.calls[0].arguments[0], companyId);
  assert.equal(list.mock.calls[0].arguments[1], false);

  const denied = await client(`/${otherCompanyId}/users?business_id=${companyId}`, {
    extraHeaders: { "x-business-id": companyId, "x-role": "PLATFORM_ADMIN" },
  });
  assert.equal(denied.status, 404);
  assert.equal(findById.mock.callCount(), 1);
  assert.equal(list.mock.callCount(), 1);
});

test("una autorización revocada durante una escritura conserva el código HTTP y omite la mutación", async (t) => {
  const update = t.mock.fn();
  let status = "unauthenticated";
  const authorizedWrite = t.mock.fn(async () => ({ status }));
  const client = await administrationClient(t, "ADMIN", { businessUsers: { update }, authorizedWrite });
  const path = `/${companyId}/users/${employeeId}`;
  const body = { name: "Nombre autorizado al iniciar la solicitud" };

  const inactive = await client(path, { method: "PATCH", body });
  assert.equal(inactive.status, 401);
  assert.equal(inactive.headers.get("www-authenticate"), "Bearer");

  status = "forbidden";
  assert.equal((await client(path, { method: "PATCH", body })).status, 403);
  status = "out_of_scope";
  assert.equal((await client(path, { method: "PATCH", body })).status, 404);
  assert.equal(authorizedWrite.mock.callCount(), 3);
  assert.equal(update.mock.callCount(), 0);
});

test("módulos permite consulta por empresa y oculta empresas ajenas", async (t) => {
  const list = t.mock.fn(async () => [{ key: "inventory", enabled: false }]);
  const client = await administrationClient(t, "EMPLOYEE", { businessModules: { list } });
  const own = await client(`/${companyId}/modules`);
  assert.equal(own.status, 200);
  assert.deepEqual(await own.json(), [{ key: "inventory", enabled: false }]);
  assert.equal(own.headers.get("cache-control"), "no-store");

  const crossScope = await client(`/${otherCompanyId}/modules`, {
    extraHeaders: { "x-business-id": companyId, "x-role": "PLATFORM_ADMIN" },
  });
  assert.equal(crossScope.status, 404);
  assert.deepEqual(list.mock.calls[0].arguments, [companyId]);
  assert.equal(list.mock.callCount(), 1);
});

test("solo PLATFORM_ADMIN puede guardar un booleano para un módulo registrado", async (t) => {
  const setEnabled = t.mock.fn(async (_client, id, key, enabled) =>
    id === companyId ? { key, enabled } : undefined
  );
  const administration = { businessModules: { setEnabled } };
  const admin = await administrationClient(t, "ADMIN", administration);
  const platform = await administrationClient(t, "PLATFORM_ADMIN", administration);
  const path = `/${companyId}/modules/inventory`;
  const put = (client, url, body) => client(url, { method: "PUT", body });

  assert.equal((await put(admin, path, { enabled: true })).status, 403);
  assert.equal((await put(platform, `/${companyId}/modules/sales`, { enabled: true })).status, 400);
  for (const body of [{}, { enabled: "false" }, { enabled: true, business_id: otherCompanyId }, [true]]) {
    assert.equal((await put(platform, path, body)).status, 400);
  }
  assert.equal(setEnabled.mock.callCount(), 0);

  for (const enabled of [true, true, false]) {
    const response = await put(platform, path, { enabled });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { key: "inventory", enabled });
    assert.deepEqual(setEnabled.mock.calls.at(-1).arguments, [writeClient, companyId, "inventory", enabled]);
  }
  const missing = await put(platform, `/${otherCompanyId}/modules/inventory`, { enabled: true });
  assert.equal(missing.status, 404);
});

test("Inventario aplica sesión, rol, alcance y habilitación antes del módulo", async (t) => {
  let enabled = false;
  const isEnabled = t.mock.fn(async () => enabled);
  const administration = { businessModules: { isEnabled } };
  const employee = await administrationClient(t, "EMPLOYEE", administration);
  const platform = await administrationClient(t, "PLATFORM_ADMIN", administration);
  const anonymous = await listen(t, async () => {});
  const path = `/${companyId}/inventory/movements`;

  assert.equal((await fetch(anonymous + businessesPath + path)).status, 401);
  assert.equal((await platform(path)).status, 403);
  assert.equal((await employee(`/${otherCompanyId}/inventory/movements`)).status, 404);
  assert.equal(isEnabled.mock.callCount(), 0);

  const disabled = await employee(path);
  assert.equal(disabled.status, 403);
  assert.equal((await disabled.json()).error.code, "FORBIDDEN");
  assert.deepEqual(isEnabled.mock.calls[0].arguments, [companyId, "inventory"]);
  enabled = true;
  const passesGuard = await employee(path);
  assert.equal(passesGuard.status, 403);
  assert.equal((await passesGuard.json()).error.message, "La operación no está disponible para la sesión actual.");
  assert.equal(isEnabled.mock.callCount(), 2);
});

const categoriesPath = `/${companyId}/inventory/categories`;
const categoryId = "c870bd2b-4afe-41da-aa61-d3bea41315c7";
const categoryRow = {
  id: categoryId,
  business_id: companyId,
  name: "Herramientas",
  created_at: "2026-11-24T18:00:00.000Z",
  updated_at: "2026-11-24T18:00:00.000Z",
};

test("las categorías se listan y consultan en la empresa de la sesión", async (t) => {
  const list = t.mock.fn(async () => [categoryRow]);
  const findById = t.mock.fn(async (_businessId, id) => id === categoryId ? categoryRow : undefined);
  const employee = await administrationClient(t, "EMPLOYEE", {
    businessModules: { isEnabled: async () => true },
    categories: { list, findById },
  });
  const page = await employee(categoriesPath + "?limit=5&offset=2&business_id=" + otherCompanyId);
  assert.equal(page.status, 200);
  assert.deepEqual(await page.json(), { items: [categoryRow], limit: 5, offset: 2 });
  assert.deepEqual(list.mock.calls[0].arguments, [companyId, { limit: 5, offset: 2 }]);
  assert.equal((await employee(categoriesPath + "?limit=0")).status, 400);
  assert.equal((await employee(categoriesPath + "/mal-uuid")).status, 400);
  assert.equal((await employee(`/${otherCompanyId}/inventory/categories/${categoryId}`)).status, 404);

  const found = await employee(categoriesPath + "/" + categoryId);
  assert.deepEqual(await found.json(), categoryRow);
  assert.deepEqual(findById.mock.calls[0].arguments, [companyId, categoryId]);
  assert.equal((await employee(categoriesPath + "/" + employeeId)).status, 404);
  assert.equal(list.mock.callCount(), 1);
  assert.equal(findById.mock.callCount(), 2);
});

test("solo ADMIN crea, renombra y elimina categorías válidas", async (t) => {
  const create = t.mock.fn(async (_client, _businessId, name) => ({ ...categoryRow, name }));
  const update = t.mock.fn(async (_client, _businessId, _categoryId, name) => ({ ...categoryRow, name }));
  const remove = t.mock.fn(async () => ({ id: categoryId }));
  const lockEnabled = t.mock.fn(async () => true);
  const administration = {
    businessModules: { isEnabled: async () => true, lockEnabled },
    categories: { create, update, remove },
  };
  const employee = await administrationClient(t, "EMPLOYEE", administration);
  const platform = await administrationClient(t, "PLATFORM_ADMIN", administration);
  const admin = await administrationClient(t, "ADMIN", administration);
  const item = categoriesPath + "/" + categoryId;

  assert.equal((await employee(categoriesPath, { method: "POST", body: { name: "Material" } })).status, 403);
  assert.equal((await employee(item, { method: "PATCH", body: { name: "Material" } })).status, 403);
  assert.equal((await employee(item, { method: "DELETE" })).status, 403);
  assert.equal((await platform(categoriesPath)).status, 403);
  for (const body of [{ name: " " }, { name: "a".repeat(101) }, { name: "Material", business_id: otherCompanyId }]) {
    assert.equal((await admin(categoriesPath, { method: "POST", body })).status, 400);
  }
  assert.equal(lockEnabled.mock.callCount(), 0);

  const created = await admin(categoriesPath, { method: "POST", body: { name: "  Herramientas  " } });
  assert.equal(created.status, 201);
  assert.deepEqual(await created.json(), categoryRow);
  assert.deepEqual(create.mock.calls[0].arguments, [writeClient, companyId, "Herramientas"]);

  const renamed = await admin(item, { method: "PATCH", body: { name: "Material" } });
  assert.equal(renamed.status, 200);
  assert.equal((await renamed.json()).name, "Material");
  assert.deepEqual(update.mock.calls[0].arguments, [writeClient, companyId, categoryId, "Material"]);

  const deleted = await admin(item, { method: "DELETE" });
  assert.equal(deleted.status, 204);
  assert.equal(await deleted.text(), "");
  assert.deepEqual(remove.mock.calls[0].arguments, [writeClient, companyId, categoryId]);
  assert.equal(lockEnabled.mock.callCount(), 3);
  assert.deepEqual(lockEnabled.mock.calls[0].arguments, [writeClient, companyId, "inventory"]);
});

test("las restricciones de categorías se traducen a 409", async (t) => {
  const duplicate = Object.assign(new Error("duplicate"), { code: "23505", constraint: "categories_business_name_ci_uniq" });
  const referenceCodes = ["23001", "23503"];
  const referenceConstraint = "products_category_same_business_fk";
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    categories: {
      create: async () => { throw duplicate; },
      update: async () => { throw duplicate; },
      remove: async () => {
        throw Object.assign(new Error("foreign key"), { code: referenceCodes.shift(), constraint: referenceConstraint });
      },
    },
  });
  const item = categoriesPath + "/" + categoryId;
  for (const [path, options, message] of [
    [categoriesPath, { method: "POST", body: { name: "Material" } }, "Ya existe una categoría con ese nombre."],
    [item, { method: "PATCH", body: { name: "Material" } }, "Ya existe una categoría con ese nombre."],
    [item, { method: "DELETE" }, "La categoría tiene productos asociados."],
    [item, { method: "DELETE" }, "La categoría tiene productos asociados."],
  ]) {
    const response = await admin(path, options);
    assert.equal(response.status, 409);
    assert.deepEqual((await response.json()).error, { code: "CONFLICT", message });
  }
});

test("una desactivación antes de la escritura impide modificar categorías", async (t) => {
  const update = t.mock.fn();
  const lockEnabled = t.mock.fn(async () => false);
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true, lockEnabled },
    categories: { update },
  });
  const response = await admin(categoriesPath + "/" + categoryId, {
    method: "PATCH",
    body: { name: "Cambio bloqueado" },
  });
  assert.equal(response.status, 403);
  assert.equal((await response.json()).error.code, "FORBIDDEN");
  assert.equal(lockEnabled.mock.callCount(), 1);
  assert.equal(update.mock.callCount(), 0);
});

const productsPath = `/${companyId}/inventory/products`;
const productId = "f7eb3419-7600-4d2a-826b-760366ba79be";
const productBody = { category_id: categoryId, sku: "FER-01", name: "Clavos", unit: "KG" };

test("productos aplica paginación, filtros, empresa y visibilidad de productos activos", async (t) => {
  const list = t.mock.fn(async () => []);
  const findById = t.mock.fn(async (_businessId, _productId, activeOnly) =>
    activeOnly ? undefined : { id: productId, is_active: false }
  );
  const administration = { businessModules: { isEnabled: async () => true }, products: { list, findById } };
  const admin = await administrationClient(t, "ADMIN", administration);
  const employee = await administrationClient(t, "EMPLOYEE", administration);

  const response = await employee(productsPath + `?category_id=${categoryId}&is_active=false&low_stock=true&limit=2&offset=3`);
  assert.deepEqual(await response.json(), { items: [], limit: 2, offset: 3 });
  assert.deepEqual(list.mock.calls[0].arguments, [companyId, {
    limit: 2, offset: 3, categoryId, isActive: false, lowStock: true, activeOnly: true,
  }]);
  for (const query of ["?is_active=1", "?low_stock=true&low_stock=false", "?category_id=incorrecto", "?limit=101"]) {
    assert.equal((await admin(productsPath + query)).status, 400);
  }
  assert.equal((await employee(`/${otherCompanyId}/inventory/products/${productId}`)).status, 404);
  assert.equal((await employee(productsPath + "/" + productId)).status, 404);
  assert.deepEqual(await (await admin(productsPath + "/" + productId)).json(), { id: productId, is_active: false });
  assert.deepEqual(findById.mock.calls.map(({ arguments: args }) => args), [
    [companyId, productId, true], [companyId, productId, false],
  ]);
});

test("el alta de producto acepta decimales exactos y bloquea el stock directo", async (t) => {
  const create = t.mock.fn(async (_client, businessId, body) => ({
    ...body, business_id: businessId, stock_quantity: "0.000",
  }));
  const administration = {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { create },
  };
  const admin = await administrationClient(t, "ADMIN", administration);
  const employee = await administrationClient(t, "EMPLOYEE", administration);
  const put = (client, body) => client(productsPath, { method: "POST", body });

  assert.equal((await put(employee, productBody)).status, 403);
  for (const changes of [
    { stock_quantity: "1" }, { business_id: otherCompanyId }, { cost_price: 1.50 },
    { sale_price: "1.234" }, { sale_price: "10000000000" }, { min_stock: "1.0000" },
    { min_stock: "1e3" }, { cost_price: "1.00\n" }, { min_stock: "-1" },
    { unit: "CAJA", min_stock: "1.25" }, { category_id: "categoria" },
  ]) {
    assert.equal((await put(admin, { ...productBody, ...changes })).status, 400);
  }
  assert.equal(create.mock.callCount(), 0);

  const valid = { ...productBody, sku: " FER-01 ", cost_price: "9999999999.99", sale_price: "5.20", min_stock: "0.125" };
  const response = await put(admin, valid);
  assert.equal(response.status, 201);
  assert.equal((await response.json()).stock_quantity, "0.000");
  assert.deepEqual(create.mock.calls[0].arguments, [writeClient, companyId, { ...valid, sku: "FER-01" }]);
});

test("el cambio de unidad verifica historial y cantidades dentro de la escritura", async (t) => {
  let hasMovements = true;
  const lockForUpdate = t.mock.fn(async () => ({ unit: "KG", stock_quantity: "0.000", min_stock: "0.500" }));
  const update = t.mock.fn(async (_client, _businessId, _productId, changes) => changes);
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { lockForUpdate, hasMovements: async () => hasMovements, update },
  });
  const patch = body => admin(productsPath + "/" + productId, { method: "PATCH", body });

  assert.equal((await patch({ unit: "PZA" })).status, 409);
  hasMovements = false;
  assert.equal((await patch({ unit: "PZA" })).status, 400);
  assert.equal((await patch({ stock_quantity: "2.500" })).status, 400);
  assert.equal(update.mock.callCount(), 0);
  const valid = await patch({ unit: "PZA", min_stock: "12.000", is_active: false });
  assert.equal(valid.status, 200);
  assert.deepEqual(await valid.json(), { unit: "PZA", min_stock: "12.000", is_active: false });
  assert.deepEqual(lockForUpdate.mock.calls[0].arguments, [writeClient, companyId, productId]);
  assert.equal(update.mock.callCount(), 1);
});

test("el SKU duplicado devuelve 409 y una categoría no disponible devuelve 404", async (t) => {
  let code = "23505";
  let constraint = "products_business_sku_ci_uniq";
  const create = async () => { throw Object.assign(new Error("constraint"), { code, constraint }); };
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { create },
  });
  const first = await admin(productsPath, { method: "POST", body: productBody });
  assert.equal(first.status, 409);
  assert.equal((await first.json()).error.code, "CONFLICT");
  code = "23503";
  constraint = "products_category_same_business_fk";
  const second = await admin(productsPath, { method: "POST", body: productBody });
  assert.equal(second.status, 404);
  assert.equal((await second.json()).error.code, "NOT_FOUND");
});

const movementsPath = `/${companyId}/inventory/movements`;

test("entradas, salidas y ajustes guardan el saldo y el movimiento en el cliente autorizado", async (t) => {
  let stock = "0.000";
  const lockForUpdate = t.mock.fn(async () => ({ is_active: true, unit: "KG", stock_quantity: stock }));
  const setStock = t.mock.fn(async (_client, _business, _product, after) => { stock = after; });
  const create = t.mock.fn(async (_client, movement) => movement);
  const administration = {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { lockForUpdate, setStock },
    movements: { create },
  };
  const employee = await administrationClient(t, "EMPLOYEE", administration);
  const admin = await administrationClient(t, "ADMIN", administration);

  for (const [client, body, before, after, delta, reason] of [
    [employee, { movement_type: "IN", quantity: "0.3" }, "0.000", "0.300", "0.300", null],
    [employee, { movement_type: "OUT", quantity: "0.1", reason: "  Merma  " }, "0.300", "0.200", "-0.100", "Merma"],
    [admin, { movement_type: "ADJUSTMENT", counted_quantity: "0", reason: "Conteo" }, "0.200", "0.000", "-0.200", "Conteo"],
  ]) {
    const response = await client(movementsPath, { method: "POST", body: { product_id: productId, ...body } });
    assert.equal(response.status, 201);
    const saved = await response.json();
    assert.equal(saved.businessId, companyId);
    assert.equal(saved.userId, userProfile.id);
    assert.equal(saved.reason, reason);
    assert.deepEqual([saved.before, saved.after, saved.delta], [before, after, delta]);
    assert.deepEqual(lockForUpdate.mock.calls.at(-1).arguments, [writeClient, companyId, productId]);
    assert.deepEqual(setStock.mock.calls.at(-1).arguments, [writeClient, companyId, productId, after]);
    assert.equal(create.mock.calls.at(-1).arguments[0], writeClient);
  }
});

test("el movimiento valida cantidad, motivo, autor y rol antes de tocar existencias", async (t) => {
  const lockForUpdate = t.mock.fn();
  const employee = await administrationClient(t, "EMPLOYEE", {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { lockForUpdate },
  });
  const post = body => employee(movementsPath, { method: "POST", body: { product_id: productId, ...body } });

  for (const body of [
    { movement_type: "IN", quantity: "0.000" },
    { movement_type: "IN", quantity: 1.25 },
    { movement_type: "IN", quantity: "1.0001" },
    { movement_type: "IN", quantity: "1", user_id: employeeId },
    { movement_type: "IN", quantity: "1", business_id: otherCompanyId },
    { movement_type: "IN", quantity: "1", counted_quantity: "5" },
    { movement_type: "OUT", quantity: "1" },
    { movement_type: "OUT", quantity: "1", reason: " " },
    { movement_type: "ADJUSTMENT", counted_quantity: "1", reason: " " },
  ]) {
    assert.equal((await post(body)).status, 400);
  }

  assert.equal((await post({ movement_type: "ADJUSTMENT", counted_quantity: "0", reason: "Conteo" })).status, 403);
  assert.equal(lockForUpdate.mock.callCount(), 0);
});

test("los movimientos rechazan producto inaccesible o inactivo, fracciones y saldos inválidos", async (t) => {
  let product;
  const setStock = t.mock.fn();
  const create = t.mock.fn();
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true, lockEnabled: async () => true },
    products: { lockForUpdate: async () => product, setStock },
    movements: { create },
  });
  const post = body => admin(movementsPath, { method: "POST", body: { product_id: productId, ...body } });

  for (const [current, body, status] of [
    [undefined, { movement_type: "IN", quantity: "1" }, 404],
    [{ is_active: false, unit: "KG", stock_quantity: "0.000" }, { movement_type: "IN", quantity: "1" }, 409],
    [{ is_active: true, unit: "CAJA", stock_quantity: "0.000" }, { movement_type: "IN", quantity: "0.125" }, 400],
    [{ is_active: true, unit: "KG", stock_quantity: "1.000" }, { movement_type: "OUT", quantity: "1.001", reason: "Venta" }, 409],
    [{ is_active: true, unit: "KG", stock_quantity: "99999999999.999" }, { movement_type: "IN", quantity: "0.001" }, 409],
    [{ is_active: true, unit: "KG", stock_quantity: "0.000" }, { movement_type: "ADJUSTMENT", counted_quantity: "0", reason: "Conteo" }, 409],
  ]) {
    product = current;
    assert.equal((await post(body)).status, status);
  }

  assert.equal(setStock.mock.callCount(), 0);
  assert.equal(create.mock.callCount(), 0);
});

test("el historial usa la empresa autorizada y conserva filtros y paginación", async (t) => {
  const movement = { id: employeeId, product_id: productId, stock_after: "0.200" };
  const list = t.mock.fn(async () => [movement]);
  const deps = { businessModules: { isEnabled: async () => true }, movements: { list } };
  const admin = await administrationClient(t, "ADMIN", deps);
  const employee = await administrationClient(t, "EMPLOYEE", deps);

  assert.equal((await employee(movementsPath)).status, 403);
  assert.equal((await admin(`/${otherCompanyId}/inventory/movements`)).status, 404);
  assert.equal(list.mock.callCount(), 0);

  const query = new URLSearchParams({
    product_id: productId,
    movement_type: "OUT",
    from: "2026-11-24T10:00:00.000001-06:00",
    to: "2026-11-24T16:00:00.000002Z",
    limit: "5",
    offset: "2",
    business_id: otherCompanyId,
  });
  const response = await admin(movementsPath + "?" + query);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { items: [movement], limit: 5, offset: 2 });
  assert.deepEqual(list.mock.calls[0].arguments, [companyId, {
    productId, type: "OUT", from: "2026-11-24T16:00:00.000001Z",
    to: "2026-11-24T16:00:00.000002Z", limit: 5, offset: 2,
  }]);
});

test("el historial rechaza filtros inválidos y rangos invertidos o equivalentes", async (t) => {
  const list = t.mock.fn(async () => []);
  const admin = await administrationClient(t, "ADMIN", {
    businessModules: { isEnabled: async () => true },
    movements: { list },
  });
  const invalid = [
    { product_id: "sin-uuid" },
    { movement_type: "in" },
    { limit: "101" },
    { offset: "-1" },
    { from: "2026-02-29T10:00:00Z" },
    { from: "2026-11-24T10:00:00" },
    { from: "2026-11-24T24:00:00Z" },
    { from: "2026-11-24T10:00:00+06:60" },
    { from: "2026-11-24T10:00:00.0000001Z" },
    { from: "2026-11-24T10:00:00-06:00", to: "2026-11-24T16:00:00Z" },
    { from: "2026-11-24T16:00:00.000002Z", to: "2026-11-24T16:00:00.000001Z" },
  ];
  for (const query of invalid) {
    const response = await admin(movementsPath + "?" + new URLSearchParams(query));
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.code, "VALIDATION_ERROR");
  }
  assert.equal((await admin(movementsPath + "?movement_type=IN&movement_type=OUT")).status, 400);
  assert.equal(list.mock.callCount(), 0);

  const empty = await admin(movementsPath);
  assert.deepEqual(await empty.json(), { items: [], limit: 25, offset: 0 });
  const valid = await admin(movementsPath + "?" + new URLSearchParams({ to: "2028-02-29T00:15:00+01:00" }));
  assert.equal(valid.status, 200);
  assert.equal(list.mock.calls[1].arguments[1].to, "2028-02-28T23:15:00.000000Z");
});
