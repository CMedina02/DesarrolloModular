import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { withTransaction } from "../src/core/database/transaction.js";
import { legacyState, readLegacyObjects } from "./legacy-schema.js";

const directory = new URL("./migrations/", import.meta.url);

export class MigrationError extends Error {}

async function loadMigrations() {
  const names = (await readdir(directory)).filter((name) => name.endsWith(".sql")).sort();
  const files = [new URL("./001_schema.sql", import.meta.url)];
  const versions = new Set(["001"]);
  for (const name of names) {
    const match = /^(\d{3})_[a-z0-9_]+\.sql$/.exec(name);
    if (!match || match[1] <= "001" || versions.has(match[1])) {
      throw new MigrationError(`Nombre o versión de migración inválidos en ${name}.`);
    }
    versions.add(match[1]);
    files.push(new URL(name, directory));
  }

  return Promise.all(files.map(async (file) => {
    const name = file.pathname.split("/").at(-1);
    const source = (await readFile(file, "utf8")).replaceAll("\r\n", "\n");
    const envelope = /^(?:[ \t]*(?:--[^\n]*)?\n)*BEGIN;\n([\s\S]+)\nCOMMIT;\s*$/.exec(source);
    if (!envelope) {
      throw new MigrationError(`Se esperaba un bloque BEGIN y COMMIT en ${name}.`);
    }
    return {
      name: name.slice(0, -4),
      sql: envelope[1],
      checksum: createHash("sha256").update(source).digest("hex"),
    };
  }));
}

export async function migrate(pool, { adoptExisting = false } = {}) {
  const migrations = await loadMigrations();
  const expected = new Map(migrations.map((migration) => [migration.name, migration.checksum]));

  return withTransaction(pool, async (client) => {
    const { rows: [{ schema }] } = await client.query("SELECT current_schema() AS schema");
    if (!schema || schema === "information_schema" || schema.startsWith("pg_")) {
      throw new MigrationError("Selecciona un esquema de aplicación en DATABASE_URL.");
    }

    await client.query("SELECT pg_catalog.set_config('search_path', pg_catalog.quote_ident($1), true)", [schema]);
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtext('desarrollomodular:migrations'), hashtext($1))",
      [schema]
    );

    await client.query(`
      CREATE TABLE IF NOT EXISTS desarrollomodular_schema_migrations (
        version TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
      )
    `);
    const { rows } = await client.query("SELECT version, checksum FROM desarrollomodular_schema_migrations");
    const applied = new Map(rows.map(({ version, checksum }) => [version, checksum]));
    if (rows.some(({ version, checksum }) => expected.get(version) !== checksum) ||
        migrations.slice(0, applied.size).some(({ name }) => !applied.has(name))) {
      throw new MigrationError("El historial de migraciones no coincide con los archivos de esta versión.");
    }
    if (applied.size === migrations.length) {
      return { schema, changes: [] };
    }

    const objects = await readLegacyObjects(client, schema);
    const changes = [];
    for (const migration of migrations) {
      if (applied.has(migration.name)) continue;

      const state = legacyState(migration.name, objects);
      if (state.existing && state.missing) {
        throw new MigrationError(`La estructura de ${migration.name} está incompleta. Falta ${state.missing}.`);
      }
      if (state.existing && !adoptExisting) {
        throw new MigrationError(`Se detectó ${migration.name} sin historial. Si se instaló con los scripts oficiales, usa --adopt-existing.`);
      }

      if (!state.existing) {
        try {
          await client.query(migration.sql);
        } catch (error) {
          throw new MigrationError(`Falló la migración ${migration.name} (${error.code ?? "UNKNOWN"}).`, { cause: error });
        }
      }

      await client.query(
        "INSERT INTO desarrollomodular_schema_migrations (version, checksum) VALUES ($1, $2)",
        [migration.name, migration.checksum]
      );
      changes.push({ name: migration.name, adopted: state.existing });
    }

    return { schema, changes };
  });
}
