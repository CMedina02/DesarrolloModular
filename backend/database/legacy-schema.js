const t02Columns = {
  businesses: "id name is_active created_at updated_at",
  users: "id business_id name email password_hash role is_active created_at updated_at",
  categories: "id business_id name created_at updated_at",
  products: "id business_id category_id sku name unit cost_price sale_price stock_quantity min_stock is_active created_at updated_at",
  stock_movements: "id business_id product_id user_id movement_type quantity_delta stock_before stock_after reason created_at",
};

const legacy = {
  "001_schema": {
    tables: t02Columns,
    required: [
      "index users_email_ci_uniq",
      "index categories_business_name_ci_uniq",
      "index products_business_sku_ci_uniq",
      "constraint users.users_platform_scope_chk",
      "constraint products.products_category_same_business_fk",
      "constraint products.products_whole_units_chk",
      "constraint stock_movements.movements_product_same_business_fk",
      "constraint stock_movements.movements_user_same_business_fk",
      "constraint stock_movements.movement_delta_type_chk",
      "constraint stock_movements.movement_balance_chk",
      "constraint stock_movements.movement_reason_chk",
      "trigger products.products_initial_stock_zero_trg",
      "trigger stock_movements.stock_movements_unit_quantity_trg",
      "trigger stock_movements.stock_movements_immutable_trg",
    ],
  },
  "004_business_modules": {
    tables: { business_modules: "business_id module_key enabled" },
    required: [
      "constraint business_modules.business_modules_pkey",
      "constraint business_modules.business_modules_business_id_fkey",
      "constraint business_modules.business_modules_module_key_check",
    ],
  },
};

export async function readLegacyObjects(client, schema) {
  const result = await client.query(
    `WITH relations AS (
       SELECT c.oid, c.relname, c.relkind
       FROM pg_catalog.pg_class AS c
       JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
       WHERE n.nspname = $1
     )
     SELECT 'table ' || r.relname AS object FROM relations AS r WHERE r.relkind = 'r'
     UNION ALL
     SELECT 'column ' || r.relname || '.' || a.attname FROM relations AS r
       JOIN pg_catalog.pg_attribute AS a ON a.attrelid = r.oid
       WHERE r.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
     UNION ALL
     SELECT 'index ' || r.relname FROM relations AS r
       JOIN pg_catalog.pg_index AS i ON i.indexrelid = r.oid WHERE i.indisvalid AND i.indisunique
     UNION ALL
     SELECT 'constraint ' || r.relname || '.' || c.conname FROM relations AS r
       JOIN pg_catalog.pg_constraint AS c ON c.conrelid = r.oid WHERE c.convalidated
     UNION ALL
     SELECT 'trigger ' || r.relname || '.' || t.tgname FROM relations AS r
       JOIN pg_catalog.pg_trigger AS t ON t.tgrelid = r.oid
       WHERE NOT t.tgisinternal AND t.tgenabled IN ('O', 'A')`,
    [schema]
  );
  return new Set(result.rows.map(({ object }) => object));
}

export function legacyState(migration, objects) {
  const definition = legacy[migration];
  if (!definition) {
    return { existing: false };
  }

  const tables = Object.entries(definition.tables);
  if (!tables.some(([name]) => objects.has(`table ${name}`))) {
    return { existing: false };
  }

  const expected = tables.flatMap(([name, columns]) =>
    [`table ${name}`, ...columns.split(" ").map((column) => `column ${name}.${column}`)]
  );
  return {
    existing: true,
    missing: [...expected, ...definition.required].find((object) => !objects.has(object)),
  };
}
