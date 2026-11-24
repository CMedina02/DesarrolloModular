# Base de datos de Inventario Comercial 1.0

## Requisitos

PostgreSQL 13 o posterior y `psql`. El esquema usa UUID generados con `gen_random_uuid()` (disponible en versiones actuales de PostgreSQL).

## Instalación y migraciones

Desde `backend/`, configura `DATABASE_URL` y ejecuta `npm run migrate`.
Para incorporar una base existente instalada con los scripts oficiales de T02
o B06, sigue el procedimiento de adopción.
[Guía de instalación B12](../../docs/tasks/backend/B12.md)

El comando aplica `001_schema.sql` y las migraciones versionadas, incluida
`004_business_modules.sql`. Los scripts de demostración y pruebas se ejecutan
de forma independiente sobre una base de desarrollo. Desde la raíz del repositorio,
con `psql` y la base de desarrollo seleccionada, puedes ejecutar:

```bash
psql -X -v ON_ERROR_STOP=1 -d inventario_comercial_dev -f backend/database/002_datos_demo.sql
psql -X -v ON_ERROR_STOP=1 -d inventario_comercial_dev -f backend/database/003_pruebas.sql
```

`002_datos_demo.sql` agrega dos comercios y un catálogo de ejemplo.
`003_pruebas.sql` termina con `ROLLBACK` y puede ejecutarse con el esquema de T02
aunque la base carezca de datos demo.

## Tablas

- `businesses`: negocios y estado.
- `users`: cuentas, correo globalmente único, hash de contraseña y rol. `PLATFORM_ADMIN` no pertenece a un negocio.
- `categories`: categorías únicas por negocio.
- `products`: catálogo, SKU único por negocio, unidad, precios y existencia.
- `stock_movements`: auditoría de entradas, salidas y ajustes.
- `business_modules`: habilitación de módulos por empresa.
- `desarrollomodular_schema_migrations`: versiones aplicadas y su firma.

## Reglas principales

Productos nuevos empiezan con existencia cero. `IN` usa delta positivo; `OUT` delta negativo y motivo obligatorio; `ADJUSTMENT` requiere justificación. Cada movimiento guarda saldo anterior, delta y saldo posterior, que deben cuadrar. No se permite saldo negativo; PZA/CAJA requieren cantidades enteras. Las llaves foráneas compuestas evitan asociar productos o autores de otro negocio. El historial no admite UPDATE/DELETE por operaciones ordinarias.

El backend debe ejecutar cada cambio de existencias y su movimiento en una sola transacción, bloqueando el producto con `SELECT ... FOR UPDATE` para evitar carreras. También debe validar permisos, negocio activo y unidades antes de persistir. Estas operaciones transaccionales y la consistencia de stock global dependen de la ruta de escritura del backend; privilegios SQL con acceso directo pueden eludir el flujo.

## Seguridad y pendientes

No guardar contraseñas en texto plano ni secretos en el repositorio. El primer `PLATFORM_ADMIN` se crea con el comando descrito en B03. Los datos demo contienen empresas y catálogo. En producción, usar una cuenta de base de datos con privilegios mínimos y restringir la escritura a la API. Las pruebas de concurrencia y autorización de API se detallan en [B11](../../docs/tasks/backend/B11.md).
