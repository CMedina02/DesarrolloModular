import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createBackendApp } from "../src/backend-app.js";
import { insertFirstAdministrator } from "../src/core/auth/bootstrap.js";
import { hashPassword } from "../src/core/auth/password.js";
import { readDatabaseUrl } from "../src/core/config.js";
import { createPool } from "../src/core/database/pool.js";

const setupFiles = [
  new URL("../database/001_schema.sql", import.meta.url),
  new URL("../database/migrations/004_business_modules.sql", import.meta.url),
];

export async function startIntegration(t, configuredUrl) {
  const databaseUrl = readDatabaseUrl({ DATABASE_URL: configuredUrl });
  // The generated identifier is the only schema created or removed by this run.
  const schema = `b11_${randomBytes(12).toString("hex")}`;
  const control = createPool(databaseUrl);
  let created = false;
  let pool;
  let server;

  t.after(async () => {
    try {
      if (server?.listening) {
        const closed = once(server, "close");
        server.close();
        await closed;
      }
    } finally {
      try {
        await pool?.end();
      } finally {
        try {
          if (created) await control.query(`DROP SCHEMA ${schema} CASCADE`);
        } finally {
          await control.end();
        }
      }
    }
  });

  await control.query(`CREATE SCHEMA ${schema}`);
  created = true;

  const schemaUrl = new URL(databaseUrl);
  schemaUrl.searchParams.set("options", `-c search_path=${schema} -c statement_timeout=10000`);
  pool = createPool(schemaUrl.href);

  const result = await pool.query("SELECT current_schema() AS name");
  assert.equal(result.rows[0].name, schema);
  for (const file of setupFiles) {
    await pool.query(await readFile(file, "utf8"));
  }

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
