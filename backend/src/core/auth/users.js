import { userProfileColumns } from "../users/repository.js";

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
        `SELECT ${userProfileColumns}, u.password_hash ${activeUsers} AND lower(u.email) = lower($1)`,
        [email]
      );
      return result.rows[0];
    },

    async findById(id) {
      const result = await pool.query(
        `SELECT ${userProfileColumns} ${activeUsers} AND u.id = $1`,
        [id]
      );
      return result.rows[0];
    },
  };
}
