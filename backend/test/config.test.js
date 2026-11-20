import assert from "node:assert/strict";
import test from "node:test";
import { readConfig } from "../src/core/config.js";

const databaseUrl = "postgresql://inventario_app@127.0.0.1:5432/inventario_comercial";

test("lee la configuración y aplica valores locales cuando HOST y PORT se omiten", () => {
  assert.deepEqual(readConfig({ DATABASE_URL: databaseUrl }), {
    host: "127.0.0.1",
    port: 3000,
    databaseUrl,
  });

  assert.deepEqual(readConfig({ HOST: "0.0.0.0", PORT: "3100", DATABASE_URL: databaseUrl }), {
    host: "0.0.0.0",
    port: 3100,
    databaseUrl,
  });
});

test("rechaza una dirección de escucha vacía y los puertos inválidos", () => {
  assert.throws(() => readConfig({ HOST: " ", DATABASE_URL: databaseUrl }), /HOST/);
  for (const port of ["", "0", "65536", "3000.5", "3e3", "abc", "9".repeat(400)]) {
    assert.throws(() => readConfig({ PORT: port, DATABASE_URL: databaseUrl }), /PORT/);
  }
});

test("rechaza las URL ausentes, inválidas o sin servidor o base de datos", () => {
  for (const url of [undefined, "", "incorrecta", "https://localhost/db", "postgresql:///db", "postgresql://localhost/"]) {
    assert.throws(() => readConfig({ DATABASE_URL: url }), /DATABASE_URL/);
  }
});
