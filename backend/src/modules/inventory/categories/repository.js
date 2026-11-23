const categoryColumns = "id, business_id, name, created_at, updated_at";

export function createCategories(pool) {
  return {
    async list(businessId, { limit, offset }) {
      const result = await pool.query(
        `SELECT ${categoryColumns} FROM categories WHERE business_id = $1
         ORDER BY id LIMIT $2 OFFSET $3`,
        [businessId, limit, offset]
      );
      return result.rows;
    },

    async findById(businessId, categoryId) {
      const result = await pool.query(
        `SELECT ${categoryColumns} FROM categories WHERE business_id = $1 AND id = $2`,
        [businessId, categoryId]
      );
      return result.rows[0];
    },

    async create(client, businessId, name) {
      const result = await client.query(
        `INSERT INTO categories (business_id, name) VALUES ($1, $2) RETURNING ${categoryColumns}`,
        [businessId, name]
      );
      return result.rows[0];
    },

    async update(client, businessId, categoryId, name) {
      const result = await client.query(
        `UPDATE categories SET name = $3, updated_at = now()
         WHERE business_id = $1 AND id = $2 RETURNING ${categoryColumns}`,
        [businessId, categoryId, name]
      );
      return result.rows[0];
    },

    async remove(client, businessId, categoryId) {
      const result = await client.query(
        "DELETE FROM categories WHERE business_id = $1 AND id = $2 RETURNING id",
        [businessId, categoryId]
      );
      return result.rows[0];
    },
  };
}
