const businessColumns = "id, name, is_active, created_at, updated_at";

export function createBusinesses(pool) {
  return {
    async list({ limit, offset }) {
      const result = await pool.query(
        `SELECT ${businessColumns} FROM businesses ORDER BY id LIMIT $1 OFFSET $2`,
        [limit, offset]
      );
      return result.rows;
    },

    async findById(id) {
      const result = await pool.query(
        `SELECT ${businessColumns} FROM businesses WHERE id = $1`,
        [id]
      );
      return result.rows[0];
    },

    async create({ name, isActive = true }) {
      const result = await pool.query(
        `INSERT INTO businesses (name, is_active) VALUES ($1, $2)
         RETURNING ${businessColumns}`,
        [name, isActive]
      );
      return result.rows[0];
    },

    async update(id, { name, isActive }) {
      const result = await pool.query(
        `UPDATE businesses SET name = COALESCE($2, name),
           is_active = COALESCE($3, is_active), updated_at = now()
         WHERE id = $1 RETURNING ${businessColumns}`,
        [id, name, isActive]
      );
      return result.rows[0];
    },
  };
}
