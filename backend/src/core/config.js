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

  return { host, port, databaseUrl };
}
