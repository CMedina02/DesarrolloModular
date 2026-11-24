import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { once } from "node:events";
import { createServer } from "node:http";
import { migrate } from "../database/migrate.js";
import { createBackendApp } from "../src/backend-app.js";
import { insertFirstAdministrator } from "../src/core/auth/bootstrap.js";
import { hashPassword } from "../src/core/auth/password.js";
import { createIsolatedDatabase } from "./database.js";

export async function startIntegration(t, configuredUrl) {
  let server;
  const { pool } = await createIsolatedDatabase(t, configuredUrl, async () => {
    if (server?.listening) {
      const closed = once(server, "close");
      server.close();
      await closed;
    }
  });
  await migrate(pool);

  const password = randomBytes(24).toString("base64url");
  const email = "platform-admin@example.invalid";
  const passwordHash = await hashPassword(password);
  assert.equal(await insertFirstAdministrator(pool, { name: "Plataforma B11", email, passwordHash }), "created");

  server = createServer(createBackendApp(pool, randomBytes(32)));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const origin = `http://127.0.0.1:${server.address().port}`;

  async function call(method, path, { token, body, status = 200, headers = {} } = {}) {
    const response = await fetch(origin + path, {
      method,
      headers: {
        ...(token && { authorization: `Bearer ${token}` }),
        ...(body !== undefined && { "content-type": "application/json" }),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
    const data = response.status === 204 ? await response.text() : await response.json();
    if (status !== null) {
      assert.equal(response.status, status, `${method} ${path}`);
    }

    return { status: response.status, data };
  }

  async function login(accountEmail) {
    const { data } = await call("POST", "/api/v1/auth/login", { body: { email: accountEmail, password } });
    return data;
  }

  return { pool, call, login, email, password };
}
