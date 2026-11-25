import { insertFirstAdministrator } from "../src/core/auth/bootstrap.js";
import { normalizeEmail } from "../src/core/auth/input.js";
import { hashPassword, isValidPassword, minimumNewPasswordLength } from "../src/core/auth/password.js";
import { readDatabaseUrl } from "../src/core/config.js";
import { createPool } from "../src/core/database/pool.js";
import { normalizeName } from "../src/core/validation.js";

const invalidPasswordMessage =
  `La contraseña debe tener entre ${minimumNewPasswordLength} y 256 caracteres en una línea UTF-8.`;

async function readPassword(input) {
  const chunks = [];
  let size = 0;

  for await (const chunk of input) {
    size += chunk.length;
    if (size > 1026) {
      throw new Error("Entrada de contraseña demasiado larga.");
    }
    chunks.push(chunk);
  }

  const password = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
    .decode(Buffer.concat(chunks))
    .replace(/\r?\n$/, "");
  if (/[\r\n]/.test(password) || !isValidPassword(password, minimumNewPasswordLength)) {
    throw new Error(invalidPasswordMessage);
  }

  return password;
}

async function main(args, input) {
  const [rawName, rawEmail] = args;
  const name = normalizeName(rawName, 150);
  const email = normalizeEmail(rawEmail);

  if (args.length !== 2 || !name || !email || input.isTTY) {
    console.error('Usa npm run bootstrap:admin -- "Nombre" "correo" y envía la contraseña por stdin.');
    return 1;
  }

  let databaseUrl;
  try {
    databaseUrl = readDatabaseUrl();
  } catch (error) {
    console.error(error.message);
    return 1;
  }

  let password;
  try {
    password = await readPassword(input);
  } catch {
    console.error(invalidPasswordMessage);
    return 1;
  }

  const passwordHash = await hashPassword(password);
  const pool = createPool(databaseUrl);
  try {
    const status = await insertFirstAdministrator(pool, { name, email, passwordHash });
    if (status === "created") {
      console.info("Se creó el primer administrador de la instalación.");
      return 0;
    }

    console.error(status === "already_initialized"
      ? "Ya existe un administrador de la instalación."
      : "El correo ya está registrado.");
    return 1;
  } finally {
    await pool.end();
  }
}

try {
  process.exitCode = await main(process.argv.slice(2), process.stdin);
} catch {
  console.error("No se pudo inicializar el administrador. Verifica la conexión y la instalación de T02.");
  process.exitCode = 1;
}
