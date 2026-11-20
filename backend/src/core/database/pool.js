import pg from "pg";

const { Pool } = pg;
const healthTimeoutMs = 2000;

export function createPool(connectionString) {
  const pool = new Pool({
    connectionString,
    connectionTimeoutMillis: healthTimeoutMs,
  });

  pool.on("error", (error) => {
    console.error("PostgreSQL perdió una conexión inactiva del pool:", error.code ?? "UNKNOWN");
  });

  return pool;
}

export function checkDatabase(pool) {
  return pool.query({
    text: "SELECT 1",
    query_timeout: healthTimeoutMs,
  });
}
