import { once } from "node:events";
import { createServer } from "node:http";
import { createApp } from "./app.js";
import { createAccessTokens } from "./core/auth/token.js";
import { createAuthUsers } from "./core/auth/users.js";
import { createBusinesses } from "./core/businesses/repository.js";
import { readConfig, readJwtSecret } from "./core/config.js";
import { checkDatabase, createPool } from "./core/database/pool.js";
import { createBusinessUsers } from "./core/users/repository.js";

async function startServer({ host, port, databaseUrl, jwtSecret }) {
  const pool = createPool(databaseUrl);
  const app = createApp({
    checkDatabase: () => checkDatabase(pool),
    businesses: createBusinesses(pool),
    businessUsers: createBusinessUsers(pool),
    auth: {
      users: createAuthUsers(pool),
      tokens: createAccessTokens(jwtSecret),
    },
  });
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
