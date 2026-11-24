import { once } from "node:events";
import { createServer } from "node:http";
import { createBackendApp } from "./backend-app.js";
import { readConfig, readJwtSecret } from "./core/config.js";
import { createPool } from "./core/database/pool.js";

async function startServer({ host, port, databaseUrl, jwtSecret }) {
  const pool = createPool(databaseUrl);
  const app = createBackendApp(pool, jwtSecret);
  const server = createServer(app);

  try {
    server.listen(port, host);
    await once(server, "listening");
  } catch (error) {
    await pool.end();
    throw error;
  }

  console.info("API de DesarrolloModular escuchando en", host, "puerto", port);

  let closing = false;
  function shutdown() {
    if (closing) {
      return;
    }

    closing = true;
    server.close(async (error) => {
      try {
        await pool.end();
        if (error) {
          throw error;
        }
      } catch {
        console.error("No se pudo cerrar el backend limpiamente.");
        process.exitCode = 1;
      }
    });
  }

  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
}

let config;
try {
  config = { ...readConfig(), jwtSecret: readJwtSecret() };
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

if (config) {
  try {
    await startServer(config);
  } catch (error) {
    console.error("No se pudo iniciar el backend:", error.code ?? "UNKNOWN");
    process.exitCode = 1;
  }
}
