export const userProfileColumns = `
  u.id, u.business_id, u.name, u.email, u.role, u.is_active, u.created_at, u.updated_at
`;

export function createBusinessUsers(pool) {
  return {
    async list(businessId, mayManageAdmins, { limit, offset }) {
      const result = await pool.query(
        `SELECT ${userProfileColumns}
         FROM users AS u
         WHERE u.business_id = $1 AND ($2::boolean OR u.role = 'EMPLOYEE')
         ORDER BY u.id LIMIT $3 OFFSET $4`,
        [businessId, mayManageAdmins, limit, offset]
      );
      return result.rows;
    },

    async create(client, businessId, { name, email, passwordHash, role, isActive = true }) {
      const result = await client.query(
        `INSERT INTO users AS u (business_id, name, email, password_hash, role, is_active)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${userProfileColumns}`,
        [businessId, name, email, passwordHash, role, isActive]
      );
      return result.rows[0];
    },

    async update(client, businessId, userId, mayManageAdmins, { name, email, role, isActive }) {
      const result = await client.query(
        `UPDATE users AS u SET name = COALESCE($3, u.name),
           email = COALESCE($4, u.email), role = COALESCE($5, u.role),
           is_active = COALESCE($6, u.is_active), updated_at = now()
         WHERE u.business_id = $1 AND u.id = $2
           AND ($7::boolean OR u.role = 'EMPLOYEE')
         RETURNING ${userProfileColumns}`,
        [businessId, userId, name, email, role, isActive, mayManageAdmins]
      );
      return result.rows[0];
    },
  };
}
