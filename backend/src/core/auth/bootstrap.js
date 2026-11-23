import { withTransaction } from "../database/transaction.js";

export function insertFirstAdministrator(pool, { name, email, passwordHash }) {
  return withTransaction(pool, async (client) => {
    await client.query("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE");
    const existing = await client.query("SELECT 1 FROM users WHERE role = 'PLATFORM_ADMIN' LIMIT 1");
    let status = "already_initialized";

    if (existing.rowCount === 0) {
      const result = await client.query(
        `INSERT INTO users (name, email, password_hash, role)
         VALUES ($1, $2, $3, 'PLATFORM_ADMIN')
         ON CONFLICT (lower(email)) DO NOTHING`,
        [name, email, passwordHash]
      );
      status = result.rowCount === 1 ? "created" : "email_in_use";
    }

    return status;
  });
}
