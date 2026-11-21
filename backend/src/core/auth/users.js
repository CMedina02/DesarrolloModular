const profileColumns = `
  u.id, u.business_id, u.name, u.email, u.role, u.is_active, u.created_at, u.updated_at
`;

const activeUsers = `
  FROM users AS u
  LEFT JOIN businesses AS b ON b.id = u.business_id
  WHERE u.is_active
    AND (u.business_id IS NULL OR b.is_active)
`;

export function createAuthUsers(pool) {
  return {
    async findByEmail(email) {
      const result = await pool.query(
        `SELECT ${profileColumns}, u.password_hash ${activeUsers} AND lower(u.email) = lower($1)`,
        [email]
      );
      return result.rows[0];
    },

    async findById(id) {
      const result = await pool.query(
        `SELECT ${profileColumns} ${activeUsers} AND u.id = $1`,
        [id]
      );
      return result.rows[0];
    },
  };
}
