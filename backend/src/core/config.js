export function readConfig(env = process.env) {
  const host = (env.HOST ?? "127.0.0.1").trim();
  if (!host) {
    throw new Error("HOST debe contener una dirección de escucha.");
  }

  const portValue = env.PORT ?? "3000";
  const port = Number(portValue);
  if (!/^\d+$/.test(portValue) || port < 1 || port > 65535) {
    throw new Error("PORT debe ser un entero entre 1 y 65535.");
  }

  return { host, port, databaseUrl: readDatabaseUrl(env) };
}

export function readDatabaseUrl(env = process.env) {
  const databaseUrl = env.DATABASE_URL?.trim();
  const parsedUrl = URL.parse(databaseUrl ?? "");
  if (
    !parsedUrl ||
    !["postgresql:", "postgres:"].includes(parsedUrl.protocol) ||
    !parsedUrl.hostname ||
    parsedUrl.pathname.length < 2
  ) {
    throw new Error("DATABASE_URL debe ser una URL de PostgreSQL con servidor y base de datos.");
  }

  return databaseUrl;
}

export function readJwtSecret(env = process.env) {
  const secret = env.JWT_SECRET;
  if (secret?.length !== 64 || !/^[0-9a-f]+$/i.test(secret)) {
    throw new Error("JWT_SECRET debe contener 32 bytes en formato hexadecimal.");
  }

  return Buffer.from(secret, "hex");
}
