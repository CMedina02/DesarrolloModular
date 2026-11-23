import { moduleKeys } from "./catalog.js";

export function createBusinessModules(pool) {
  return {
    async list(businessId) {
      const result = await pool.query(
        `SELECT m.module_key, m.enabled
         FROM businesses AS b
         LEFT JOIN business_modules AS m
           ON m.business_id = b.id AND m.module_key = ANY($2::text[])
         WHERE b.id = $1`,
        [businessId, moduleKeys]
      );
      if (result.rows.length === 0) {
        return undefined;
      }

      const overrides = new Map(result.rows.map(({ module_key, enabled }) => [module_key, enabled]));
      return moduleKeys.map((key) => ({ key, enabled: overrides.get(key) ?? false }));
    },

    async setEnabled(client, businessId, key, enabled) {
      const result = await client.query(
        `INSERT INTO business_modules (business_id, module_key, enabled)
         SELECT id, $2, $3 FROM businesses WHERE id = $1 FOR KEY SHARE
         ON CONFLICT (business_id, module_key) DO UPDATE SET enabled = EXCLUDED.enabled
         RETURNING module_key AS key, enabled`,
        [businessId, key, enabled]
      );
      return result.rows[0];
    },

    async isEnabled(businessId, key) {
      const result = await pool.query(
        "SELECT enabled FROM business_modules WHERE business_id = $1 AND module_key = $2",
        [businessId, key]
      );
      return result.rows[0]?.enabled === true;
    },
  };
}
