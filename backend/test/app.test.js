import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";
import { createApp } from "../src/app.js";

async function listen(t, checkDatabase) {
  const server = createServer(createApp({ checkDatabase }));
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
