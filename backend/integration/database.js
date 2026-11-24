import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readDatabaseUrl } from "../src/core/config.js";
import { createPool } from "../src/core/database/pool.js";

export async function createIsolatedDatabase(t, configuredUrl, beforeClose) {
  const databaseUrl = readDatabaseUrl({ DATABASE_URL: configuredUrl });
  const schema = `dm_test_${randomBytes(12).toString("hex")}`;
  const control = createPool(databaseUrl);
  let created = false;
  let pool;

  t.after(async () => {
    try {
      await beforeClose?.();
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

  const isolatedUrl = new URL(databaseUrl);
  isolatedUrl.searchParams.set("options", `-c search_path=${schema} -c statement_timeout=10000`);
  pool = createPool(isolatedUrl.href);

  const { rows: [current] } = await pool.query("SELECT current_schema() AS name");
  assert.equal(current.name, schema);
  return { pool, schema, url: isolatedUrl.href };
}
