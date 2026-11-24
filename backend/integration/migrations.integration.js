import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { migrate } from "../database/migrate.js";
import { createIsolatedDatabase } from "./database.js";

const run = promisify(execFile);
const cli = fileURLToPath(new URL("../scripts/migrate.js", import.meta.url));
const initial = new URL("../database/001_schema.sql", import.meta.url);
const modules = new URL("../database/migrations/004_business_modules.sql", import.meta.url);
const checks = new URL("../database/003_pruebas.sql", import.meta.url);
const versions = ["001_schema", "004_business_modules"];

function runCli(url, ...args) {
  return run(process.execPath, [cli, ...args], {
    env: { ...process.env, DATABASE_URL: url },
    timeout: 15_000,
  });
}

async function history(pool) {
  const { rows } = await pool.query("SELECT version, checksum, applied_at FROM desarrollomodular_schema_migrations ORDER BY version");
  return rows;
}

async function hasObject(pool, schema, name) {
  const { rows: [row] } = await pool.query(
    "SELECT to_regclass(format('%I.%I', $1::text, $2::text)) IS NOT NULL AS exists",
    [schema, name]
  );
  return row.exists;
}

test("B12 · Migraciones reproducibles con PostgreSQL", { timeout: 90_000 }, async (t) => {
  const configuredUrl = process.env.INTEGRATION_DATABASE_URL;
  assert(configuredUrl, "Configura INTEGRATION_DATABASE_URL. Consulta docs/tasks/backend/B12.md.");

  await t.test("instalación vacía, dos ejecuciones simultáneas y repetición", async (t) => {
    const { pool, schema, url } = await createIsolatedDatabase(t, configuredUrl);
    const results = await Promise.all([runCli(url), runCli(url)]);
    const output = results.map(({ stdout }) => stdout).join("\n");
    for (const version of versions) {
      assert.equal(output.split(`${version}: aplicada`).length, 2);
    }
    assert.match(output, /Sin migraciones pendientes/);
    const installed = await history(pool);
    assert.deepEqual(installed.map(({ version }) => version), versions);
    assert(installed.every(({ checksum }) => /^[a-f0-9]{64}$/.test(checksum)));
    assert.equal(await hasObject(pool, schema, "stock_movements"), true);
    assert.equal(await hasObject(pool, schema, "business_modules"), true);
    assert.deepEqual(await migrate(pool), { schema, changes: [] });
    assert.deepEqual(await history(pool), installed);
    await pool.query(await readFile(checks, "utf8"));
    const { rows: [row] } = await pool.query("SELECT count(*)::int AS count FROM businesses");
    assert.equal(row.count, 0);
  });

  await t.test("adopta T02 y aplica B06 conservando datos", async (t) => {
    const { pool, schema, url } = await createIsolatedDatabase(t, configuredUrl);
    await pool.query(await readFile(initial, "utf8"));
    const { rows: [business] } = await pool.query("INSERT INTO businesses(name) VALUES ('Existente') RETURNING id, name");
    await assert.rejects(runCli(url), (error) => error.code === 1 && /--adopt-existing/.test(error.stderr));
    assert.equal(await hasObject(pool, schema, "desarrollomodular_schema_migrations"), false);
    const { stdout } = await runCli(url, "--adopt-existing");
    assert.match(stdout, /001_schema: adoptada/);
    assert.match(stdout, /004_business_modules: aplicada/);
    const { rows } = await pool.query("SELECT id, name FROM businesses");
    assert.deepEqual(rows, [business]);
  });

  await t.test("adopta también B06 cuando ya está instalado y conserva su configuración", async (t) => {
    const { pool } = await createIsolatedDatabase(t, configuredUrl);
    await pool.query(await readFile(initial, "utf8"));
    await pool.query(await readFile(modules, "utf8"));
    const { rows: [business] } = await pool.query("INSERT INTO businesses(name) VALUES ('Existente') RETURNING id");
    await pool.query("INSERT INTO business_modules VALUES ($1, 'inventory', true)", [business.id]);
    const { changes } = await migrate(pool, { adoptExisting: true });
    assert.deepEqual(changes, versions.map((name) => ({ name, adopted: true })));
    const { rows } = await pool.query("SELECT * FROM business_modules");
    assert.deepEqual(rows, [{ business_id: business.id, module_key: "inventory", enabled: true }]);
  });

  await t.test("una estructura previa parcial se rechaza antes de modificarla", async (t) => {
    const { pool, schema } = await createIsolatedDatabase(t, configuredUrl);
    await pool.query("CREATE TABLE users (id UUID)");
    await assert.rejects(migrate(pool, { adoptExisting: true }), /estructura.+incompleta/);
    assert.equal(await hasObject(pool, schema, "users"), true);
    assert.equal(await hasObject(pool, schema, "businesses"), false);
    assert.equal(await hasObject(pool, schema, "desarrollomodular_schema_migrations"), false);
  });

  await t.test("una migración fallida revierte el lote y su historial", async (t) => {
    const { pool, schema } = await createIsolatedDatabase(t, configuredUrl);
    await pool.query("CREATE VIEW business_modules AS SELECT 1 AS keep");
    await assert.rejects(migrate(pool), /Falló la migración 004_business_modules/);
    assert.equal(await hasObject(pool, schema, "businesses"), false);
    assert.equal(await hasObject(pool, schema, "desarrollomodular_schema_migrations"), false);
    const { rows } = await pool.query("SELECT keep FROM business_modules");
    assert.deepEqual(rows, [{ keep: 1 }]);
  });

  await t.test("la firma del historial detecta una versión alterada", async (t) => {
    const { pool } = await createIsolatedDatabase(t, configuredUrl);
    await migrate(pool);
    await pool.query("UPDATE desarrollomodular_schema_migrations SET checksum = 'alterada' WHERE version = $1", [versions[0]]);
    await assert.rejects(migrate(pool), /historial de migraciones no coincide/);
  });
});
