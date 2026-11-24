import assert from "node:assert/strict";
import test from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { startIntegration } from "./harness.js";

const businessesPath = "/api/v1/businesses";

async function provisionCompany(api, platform, suffix) {
  const { data: business } = await api.call("POST", businessesPath, {
    token: platform, body: { name: `Comercio ${suffix}` }, status: 201,
  });
  const path = `${businessesPath}/${business.id}`;
  const users = {};
  for (const role of ["ADMIN", "EMPLOYEE"]) {
    const email = `${role.toLowerCase()}-${suffix}@example.invalid`;
    const { data: user } = await api.call("POST", path + "/users", {
      token: platform, body: { name: `Cuenta ${role} ${suffix}`, role, email, password: api.password }, status: 201,
    });
    const session = await api.login(email);
    assert.equal(session.user.id, user.id);
    assert.equal(session.user.business_id, business.id);
    assert.equal(session.user.role, role);
    users[role] = { id: user.id, token: session.access_token };
  }

  const { data: modules } = await api.call("GET", path + "/modules", { token: users.ADMIN.token });
  assert.deepEqual(modules, [{ key: "inventory", enabled: false }]);
  await api.call("PUT", path + "/modules/inventory", { token: platform, body: { enabled: true } });
  const inventory = path + "/inventory";
  const { data: category } = await api.call("POST", inventory + "/categories", {
    token: users.ADMIN.token, body: { name: "Herramientas" }, status: 201,
  });
  return { id: business.id, path, inventory, categoryId: category.id, ...users };
}

async function newProduct(api, company, sku) {
  const { data: product } = await api.call("POST", company.inventory + "/products", {
    token: company.ADMIN.token,
    body: { category_id: company.categoryId, sku, name: sku, unit: "KG", sale_price: "19.90" },
    status: 201,
  });
  assert.equal(product.stock_quantity, "0.000");
  assert.equal(product.sale_price, "19.90");
  return product;
}

function move(api, company, product, token, body, status = 201) {
  return api.call("POST", company.inventory + "/movements", {
    token,
    body: { product_id: product.id, ...body },
    status,
  });
}

async function checkBalance(api, company, product, expected, movementCount) {
  const { data: current } = await api.call("GET", company.inventory + "/products/" + product.id, {
    token: company.ADMIN.token,
  });
  const query = new URLSearchParams({ product_id: product.id });
  const { data: history } = await api.call("GET", company.inventory + "/movements?" + query, {
    token: company.ADMIN.token,
  });
  assert.equal(current.stock_quantity, expected);
  assert.equal(history.items.length, movementCount);
  assert.equal(history.items[0]?.stock_after ?? "0.000", expected);
  return history.items;
}

test("B11 · Integración de Inventario con PostgreSQL", { timeout: 90_000 }, async (t) => {
  const url = process.env.INTEGRATION_DATABASE_URL;
  assert(url, "Configura INTEGRATION_DATABASE_URL con una base PostgreSQL de pruebas. Consulta docs/tasks/backend/B11.md.");
  const api = await startIntegration(t, url);
  await api.call("GET", "/health");
  await api.call("GET", "/health/db");

  const session = await api.login(api.email);
  assert.equal(session.token_type, "Bearer");
  assert.equal(session.expires_in, 900);
  assert.equal(session.user.role, "PLATFORM_ADMIN");
  const platform = session.access_token;
  const a = await provisionCompany(api, platform, "a");
  const b = await provisionCompany(api, platform, "b");

  await t.test("flujo de catálogo, entrada, salida, ajuste e historial", async () => {
    const { data: profile } = await api.call("GET", "/api/v1/auth/me", { token: a.ADMIN.token });
    assert.equal(profile.business_id, a.id);
    assert(!Object.hasOwn(profile, "password_hash"));
    const product = await newProduct(api, a, "FLUJO");
    const { data: entry } = await move(api, a, product, a.EMPLOYEE.token, {
      movement_type: "IN", quantity: "2.500",
    });
    assert.equal(entry.user_id, a.EMPLOYEE.id);
    const { data: exit } = await move(api, a, product, a.EMPLOYEE.token, {
      movement_type: "OUT", quantity: "0.750", reason: "Venta",
    });
    const { data: adjustment } = await move(api, a, product, a.ADMIN.token, {
      movement_type: "ADJUSTMENT", counted_quantity: "1.500", reason: "Conteo",
    });
    assert.equal(adjustment.user_id, a.ADMIN.id);
    assert.deepEqual([entry, exit, adjustment].map((row) => [row.stock_before, row.quantity_delta, row.stock_after]), [
      ["0.000", "2.500", "2.500"],
      ["2.500", "-0.750", "1.750"],
      ["1.750", "-0.250", "1.500"],
    ]);
    assert.deepEqual(await checkBalance(api, a, product, "1.500", 3), [adjustment, exit, entry]);
  });

  await t.test("roles, aislamiento de empresas y desactivación de módulos", async () => {
    const own = await newProduct(api, a, "COMUN");
    const foreign = await newProduct(api, b, "comun");
    const activate = (enabled) => api.call("PUT", a.path + "/modules/inventory", {
      token: platform, body: { enabled },
    });

    await api.call("GET", a.inventory + "/products", { status: 401 });
    await api.call("GET", a.inventory + "/products", { token: platform, status: 403 });
    await api.call("GET", a.inventory + "/movements", { token: a.EMPLOYEE.token, status: 403 });
    await move(api, a, own, a.EMPLOYEE.token, {
      movement_type: "ADJUSTMENT", counted_quantity: "1", reason: "Conteo",
    }, 403);
    await api.call("GET", b.inventory + "/products", {
      token: a.ADMIN.token, headers: { "x-business-id": b.id }, status: 404,
    });
    await api.call("GET", a.inventory + "/products/" + foreign.id, { token: a.ADMIN.token, status: 404 });
    await move(api, a, foreign, a.ADMIN.token, { movement_type: "IN", quantity: "1" }, 404);
    const { data: foreignHistory } = await api.call("GET", a.inventory + "/movements?" +
      new URLSearchParams({ product_id: foreign.id }), { token: a.ADMIN.token });
    assert.deepEqual(foreignHistory.items, []);
    await api.call("PUT", a.path + "/modules/inventory", {
      token: a.ADMIN.token, body: { enabled: false }, status: 403,
    });

    await move(api, a, own, a.ADMIN.token, { movement_type: "IN", quantity: "2" });
    await activate(false);
    try {
      await api.call("GET", a.inventory + "/products", { token: a.ADMIN.token, status: 403 });
      await move(api, a, own, a.ADMIN.token, { movement_type: "IN", quantity: "1" }, 403);
      await api.call("GET", b.inventory + "/products", { token: b.EMPLOYEE.token });
    } finally {
      await activate(true);
    }
    await checkBalance(api, a, own, "2.000", 1);
    await checkBalance(api, b, foreign, "0.000", 0);
  });

  await t.test("dos salidas concurrentes mantienen el saldo y registran un solo movimiento de salida", async () => {
    const product = await newProduct(api, a, "CONCURRENCIA");
    await move(api, a, product, a.ADMIN.token, { movement_type: "IN", quantity: "1.200" });
    const exits = await Promise.all([a.ADMIN.token, a.EMPLOYEE.token].map((token) =>
      move(api, a, product, token, { movement_type: "OUT", quantity: "0.800", reason: "Pedido" }, null)
    ));
    assert.deepEqual(exits.map(({ status }) => status).sort(), [201, 409]);
    assert.equal(exits.find(({ status }) => status === 409).data.error.code, "CONFLICT");
    const history = await checkBalance(api, a, product, "0.400", 2);
    assert.equal(history.filter((row) => row.movement_type === "OUT").length, 1);
  });

  await t.test("un fallo al registrar el historial revierte el stock y el historial sigue inmutable", async () => {
    const product = await newProduct(api, a, "REVERSION");
    const { data: original } = await move(api, a, product, a.ADMIN.token, { movement_type: "IN", quantity: "1" });
    await api.pool.query(`
      CREATE FUNCTION b11_reject_test_movement() RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.reason = 'B11 rollback' THEN
          RAISE EXCEPTION 'Fallo simulado del historial B11';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER b11_reject_test_movement BEFORE INSERT ON stock_movements
        FOR EACH ROW EXECUTE FUNCTION b11_reject_test_movement();
    `);

    const { data: error } = await move(api, a, product, a.ADMIN.token, {
      movement_type: "IN", quantity: "2", reason: "B11 rollback",
    }, 500);
    assert.equal(error.error.code, "INTERNAL_ERROR");
    assert.deepEqual(await checkBalance(api, a, product, "1.000", 1), [original]);
    await assert.rejects(api.pool.query("DELETE FROM stock_movements WHERE id = $1", [original.id]), /inmutables/);
  });

  await t.test("revocar el rol durante una escritura impide que la mutación se confirme", async () => {
    const product = await newProduct(api, a, "REVOCACION");
    const blocker = await api.pool.connect();
    let pending;
    try {
      const { rows: [{ pid }] } = await blocker.query("SELECT pg_backend_pid() AS pid");
      await blocker.query("BEGIN");
      await blocker.query("UPDATE users SET role = 'EMPLOYEE' WHERE id = $1", [a.ADMIN.id]);
      pending = api.call("PATCH", a.inventory + "/products/" + product.id, {
        token: a.ADMIN.token, body: { name: "Cambio sin permiso" }, status: 403,
      });
      pending.catch(() => {});
      let waiting = false;
      for (let attempt = 0; attempt < 100; attempt++) {
        const blocked = await api.pool.query(
          "SELECT 1 FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid)) AND query LIKE '%FOR SHARE%'",
          [pid]
        );
        if (blocked.rowCount > 0) {
          waiting = true;
          break;
        }
        await delay(25);
      }
      assert(waiting, "La escritura debe esperar a que termine el cambio de rol.");
      await blocker.query("COMMIT");
      assert.equal((await pending).data.error.code, "FORBIDDEN");
      const { data: unchanged } = await api.call("GET", a.inventory + "/products/" + product.id, {
        token: a.ADMIN.token,
      });
      assert.equal(unchanged.name, "REVOCACION");
    } finally {
      try {
        await blocker.query("ROLLBACK");
      } finally {
        if (pending) await pending.catch(() => {});
        blocker.release();
      }
    }
  });
});
