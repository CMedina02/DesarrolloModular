import { migrate, MigrationError } from "../database/migrate.js";
import { readDatabaseUrl } from "../src/core/config.js";
import { createPool } from "../src/core/database/pool.js";

async function main(args) {
  const adoptExisting = args.length === 1 && args[0] === "--adopt-existing";
  if (args.length !== 0 && !adoptExisting) {
    console.error("Usa npm run migrate o npm run migrate -- --adopt-existing.");
    return 1;
  }

  let databaseUrl;
  try {
    databaseUrl = readDatabaseUrl();
  } catch (error) {
    console.error(error.message);
    return 1;
  }

  const pool = createPool(databaseUrl);
  try {
    const { schema, changes } = await migrate(pool, { adoptExisting });
    for (const change of changes) {
      console.log(`${change.name}: ${change.adopted ? "adoptada" : "aplicada"}`);
    }
    console.log(changes.length === 0 ? `Sin migraciones pendientes en ${schema}.` : `Migraciones confirmadas en ${schema}.`);
    return 0;
  } finally {
    await pool.end();
  }
}

try {
  process.exitCode = await main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof MigrationError ? error.message : `No se pudieron ejecutar las migraciones (${error.code ?? "UNKNOWN"}).`);
  process.exitCode = 1;
}
