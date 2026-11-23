import { withTransaction } from "../database/transaction.js";

export function createAuthorizedWrite(pool) {
  return (session, operation) => withTransaction(pool, async (client) => {
    const { rows: [actor] } = await client.query(
      "SELECT business_id, role, is_active FROM users WHERE id = $1 FOR SHARE",
      [session.id]
    );
    if (!actor?.is_active) {
      return { status: "unauthenticated" };
    }

    if (actor.business_id !== session.business_id) {
      return { status: "out_of_scope" };
    }
    if (actor.business_id !== null) {
      const { rows: [business] } = await client.query(
        "SELECT is_active FROM businesses WHERE id = $1 FOR SHARE",
        [actor.business_id]
      );
      if (!business?.is_active) {
        return { status: "unauthenticated" };
      }
    }

    if (actor.role !== session.role) {
      return { status: "forbidden" };
    }

    return { status: "authorized", resource: await operation(client) };
  });
}
