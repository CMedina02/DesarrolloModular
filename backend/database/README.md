# Base de datos — Inventario Comercial 1.0 (T02)

## Requisitos

PostgreSQL 13 o posterior y `psql`. El esquema usa UUID generados con `gen_random_uuid()` (disponible en versiones actuales de PostgreSQL).

## Preparación local

Crea una base de desarrollo vacía con una cuenta local autorizada:

```bash
createdb inventario_comercial_dev
psql -X -v ON_ERROR_STOP=1 -d inventario_comercial_dev -f backend/database/001_schema.sql
psql -X -v ON_ERROR_STOP=1 -d inventario_comercial_dev -f backend/database/002_datos_demo.sql
psql -X -v ON_ERROR_STOP=1 -d inventario_comercial_dev -f backend/database/003_pruebas.sql
```

`001_schema.sql` se ejecuta una vez sobre una base vacía. `002_datos_demo.sql` agrega dos comercios y un catálogo de ejemplo; no crea credenciales. No ejecutar los datos demo en producción. `003_pruebas.sql` usa una transacción y termina con `ROLLBACK`. Para pruebas aisladas, ejecútalo después del esquema; no depende de los datos demo.

## Tablas

- `businesses`: negocios y estado.
- `users`: cuentas, correo globalmente único, hash de contraseña y rol. `PLATFORM_ADMIN` no pertenece a un negocio.
- `categories`: categorías únicas por negocio.
- `products`: catálogo, SKU único por negocio, unidad, precios y existencia.
- `stock_movements`: auditoría de entradas, salidas y ajustes.

## Reglas principales

Productos nuevos empiezan con existencia cero. `IN` usa delta positivo; `OUT` delta negativo y motivo obligatorio; `ADJUSTMENT` requiere justificación. Cada movimiento guarda saldo anterior, delta y saldo posterior, que deben cuadrar. No se permite saldo negativo; PZA/CAJA requieren cantidades enteras. Las llaves foráneas compuestas evitan asociar productos o autores de otro negocio. El historial no admite UPDATE/DELETE por operaciones ordinarias.

El backend debe ejecutar cada cambio de existencias y su movimiento en una sola transacción, bloqueando el producto con `SELECT ... FOR UPDATE` para evitar carreras. También debe validar permisos, negocio activo y unidades antes de persistir. Estas operaciones transaccionales y la consistencia de stock global dependen de la ruta de escritura del backend; privilegios SQL con acceso directo pueden eludir el flujo.

## Seguridad y pendientes

No guardar contraseñas en texto plano ni secretos en el repositorio. Esta etapa no incluye bootstrap de `PLATFORM_ADMIN`; los datos demo omiten usuarios para no distribuir credenciales conocidas. En producción, usar una cuenta de base de datos con privilegios mínimos y restringir la escritura a la API. Las pruebas SQL no cubren concurrencia ni autorización de API; corresponden a etapas posteriores.
