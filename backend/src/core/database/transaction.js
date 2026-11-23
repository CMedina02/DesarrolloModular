export async function withTransaction(pool, operation) {
  const client = await pool.connect();
  let discardClient = false;

  try {
    await client.query("BEGIN ISOLATION LEVEL READ COMMITTED");
    const result = await operation(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      discardClient = true;
    }
    throw error;
  } finally {
    client.release(discardClient);
  }
}
