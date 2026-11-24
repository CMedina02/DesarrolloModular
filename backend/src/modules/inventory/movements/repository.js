export const movementRepository = {
  async create(client, { businessId, productId, userId, type, reason, before, after, delta }) {
    const result = await client.query(
      `INSERT INTO stock_movements (
         business_id, product_id, user_id, movement_type,
         stock_before, stock_after, quantity_delta, reason, created_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, clock_timestamp())
       RETURNING id, business_id, product_id, user_id, movement_type,
                 quantity_delta, stock_before, stock_after, reason, created_at`,
      [businessId, productId, userId, type, before, after, delta, reason]
    );
    return result.rows[0];
  },
};
