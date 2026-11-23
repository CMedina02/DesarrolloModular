import assert from "node:assert/strict";
import test from "node:test";
import { createAuthorizedWrite } from "../src/core/security/authorized-write.js";

const session = {
  id: "139e792c-2847-4bbd-a5cd-f4cef3aa0820",
  business_id: "76c6e84c-ebcb-4a4a-97ca-54072b8f03b7",
  role: "ADMIN",
};
const activeActor = { role: session.role, business_id: session.business_id, is_active: true };
const selectActor = "SELECT business_id, role, is_active FROM users WHERE id = $1 FOR SHARE";
const selectBusiness = "SELECT is_active FROM businesses WHERE id = $1 FOR SHARE";

function fixture(t, { actor = activeActor, business = { is_active: true }, rollbackError = false } = {}) {
  const query = t.mock.fn(async (sql) => {
    if (sql === selectActor) return { rows: actor ? [actor] : [] };
    if (sql === selectBusiness) return { rows: business ? [business] : [] };
    if (sql === "ROLLBACK" && rollbackError) throw new Error("Fallo de conexión");
    return {};
  });
  const client = { query, release: t.mock.fn() };
  return { client, write: createAuthorizedWrite({ connect: async () => client }) };
}

test("el permiso y la mutación se verifican en la misma transacción", async (t) => {
  const { client, write } = fixture(t);
  const result = await write(session, async (transactionClient) => {
    assert.strictEqual(transactionClient, client);
    await transactionClient.query("COMPROBAR MUTACIÓN");
    return { id: session.id };
  });
  assert.deepEqual(result, { status: "authorized", resource: { id: session.id } });
  assert.deepEqual(client.query.mock.calls.map(({ arguments: args }) => args), [
    ["BEGIN ISOLATION LEVEL READ COMMITTED"],
    [selectActor, [session.id]],
    [selectBusiness, [session.business_id]],
    ["COMPROBAR MUTACIÓN"],
    ["COMMIT"],
  ]);
  assert.deepEqual(client.release.mock.calls[0].arguments, [false]);
});

test("rechaza cambios de estado, empresa o rol antes de ejecutar la mutación", async (t) => {
  for (const [state, expected] of [
    [{ actor: null }, "unauthenticated"],
    [{ actor: { ...activeActor, is_active: false } }, "unauthenticated"],
    [{ business: { is_active: false } }, "unauthenticated"],
    [{ actor: { ...activeActor, business_id: "empresa-distinta" } }, "out_of_scope"],
    [{ actor: { ...activeActor, role: "EMPLOYEE" } }, "forbidden"],
  ]) {
    const { client, write } = fixture(t, state);
    const operation = t.mock.fn();
    assert.deepEqual(await write(session, operation), { status: expected });
    assert.equal(operation.mock.callCount(), 0);
    assert.equal(client.release.mock.callCount(), 1);
  }
});

test("el administrador de plataforma revalida su cuenta sin exigir una empresa asignada", async (t) => {
  const platform = { ...session, role: "PLATFORM_ADMIN", business_id: null };
  const { client, write } = fixture(t, { actor: { ...platform, is_active: true } });
  assert.deepEqual(await write(platform, async () => "resultado"), {
    status: "authorized",
    resource: "resultado",
  });
  assert(!client.query.mock.calls.some(({ arguments: [sql] }) => sql === selectBusiness));
});

test("una mutación fallida ejecuta rollback y descarta la conexión si rollback falla", async (t) => {
  const failure = new Error("Mutación fallida");
  for (const rollbackError of [false, true]) {
    const { client, write } = fixture(t, { rollbackError });
    await assert.rejects(write(session, async () => { throw failure; }), (error) => error === failure);
    assert.equal(client.query.mock.calls.at(-1).arguments[0], "ROLLBACK");
    assert.deepEqual(client.release.mock.calls[0].arguments, [rollbackError]);
  }
});
