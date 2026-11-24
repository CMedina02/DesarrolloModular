const movementColumns = `
  id, business_id, product_id, user_id, movement_type, quantity_delta, stock_before, stock_after, reason,
  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created_at
`;

export function createMovements(pool) {
  return {
    async list(businessId, { limit, offset, productId, type, from, to }) {
      const result = await pool.query(
        `SELECT ${movementColumns}
         FROM stock_movements AS m
         WHERE m.business_id = $1
           AND ($2::uuid IS NULL OR m.product_id = $2)
           AND ($3::text IS NULL OR m.movement_type = $3)
           AND ($4::timestamptz IS NULL OR m.created_at >= $4)
           AND ($5::timestamptz IS NULL OR m.created_at < $5)
         ORDER BY m.created_at DESC, m.id DESC
         LIMIT $6 OFFSET $7`,
        [businessId, productId, type, from, to, limit, offset]
      );
      return result.rows;
    },

    async create(client, { businessId, productId, userId, type, reason, before, after, delta }) {
      const result = await client.query(
        `INSERT INTO stock_movements (
           business_id, product_id, user_id, movement_type,
           stock_before, stock_after, quantity_delta, reason, created_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, clock_timestamp())
         RETURNING ${movementColumns}`,
        [businessId, productId, userId, type, before, after, delta, reason]
      );
      return result.rows[0];
    },
  };
}
