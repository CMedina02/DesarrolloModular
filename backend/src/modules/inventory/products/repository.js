const columns = `
  id, business_id, category_id, sku, name, unit, cost_price, sale_price,
  stock_quantity, min_stock, is_active, created_at, updated_at
`;

export function createProducts(pool) {
  return {
    async list(businessId, { limit, offset, categoryId, isActive, lowStock, activeOnly }) {
      const result = await pool.query(
        `SELECT ${columns} FROM products
         WHERE business_id = $1
           AND ($2::uuid IS NULL OR category_id = $2)
           AND ($3::boolean IS NULL OR is_active = $3)
           AND (NOT $4::boolean OR stock_quantity <= min_stock)
           AND (NOT $5::boolean OR is_active)
         ORDER BY id LIMIT $6 OFFSET $7`,
        [businessId, categoryId, isActive, lowStock, activeOnly, limit, offset]
      );
      return result.rows;
    },

    async findById(businessId, productId, activeOnly) {
      const result = await pool.query(
        `SELECT ${columns} FROM products
         WHERE business_id = $1 AND id = $2 AND (NOT $3::boolean OR is_active)`,
        [businessId, productId, activeOnly]
      );
      return result.rows[0];
    },

    async create(client, businessId, product) {
      const result = await client.query(
        `INSERT INTO products (business_id, category_id, sku, name, unit, cost_price,
                               sale_price, min_stock, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         RETURNING ${columns}`,
        [businessId, product.category_id, product.sku, product.name, product.unit,
          product.cost_price ?? "0", product.sale_price ?? "0", product.min_stock ?? "0",
          product.is_active ?? true]
      );
      return result.rows[0];
    },

    async lockForUpdate(client, businessId, productId) {
      const result = await client.query(
        `SELECT unit, stock_quantity, min_stock, is_active FROM products
         WHERE business_id = $1 AND id = $2 FOR UPDATE`,
        [businessId, productId]
      );
      return result.rows[0];
    },

    async setStock(client, businessId, productId, stockQuantity) {
      await client.query(
        `UPDATE products SET stock_quantity = $3, updated_at = clock_timestamp()
         WHERE business_id = $1 AND id = $2`,
        [businessId, productId, stockQuantity]
      );
    },

    async hasMovements(client, businessId, productId) {
      const result = await client.query(
        `SELECT EXISTS(
           SELECT 1 FROM stock_movements WHERE business_id = $1 AND product_id = $2
         ) AS has_movements`,
        [businessId, productId]
      );
      return result.rows[0].has_movements;
    },

    async update(client, businessId, productId, changes) {
      const result = await client.query(
        `UPDATE products SET
           category_id = COALESCE($3, category_id),
           sku = COALESCE($4, sku),
           name = COALESCE($5, name),
           unit = COALESCE($6, unit),
           cost_price = COALESCE($7, cost_price),
           sale_price = COALESCE($8, sale_price),
           min_stock = COALESCE($9, min_stock),
           is_active = COALESCE($10, is_active),
           updated_at = now()
         WHERE business_id = $1 AND id = $2
         RETURNING ${columns}`,
        [businessId, productId, changes.category_id, changes.sku, changes.name, changes.unit,
          changes.cost_price, changes.sale_price, changes.min_stock, changes.is_active]
      );
      return result.rows[0];
    },
  };
}
