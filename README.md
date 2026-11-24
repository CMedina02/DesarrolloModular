# Desarrollo Modular

Repositorio para una plataforma modular orientada a pequeños comercios. El primer módulo es Inventario Comercial 1.0.

## Estructura

- `backend/database/`: esquema PostgreSQL, datos de demostración y pruebas de integridad de T02.
- `backend/src/`: servidor Express, configuración y acceso compartido a PostgreSQL.
- `mobile/`: reservado para la aplicación Flutter de etapas posteriores.
- `docs/`: documentación del proyecto.

## Instalación del backend

Requiere Node.js 22.21 o posterior y una base PostgreSQL. Desde `backend/`,
instala las dependencias con `npm ci` y prepara `.env` a partir de
`.env.example`. Configura `DATABASE_URL` y una clave `JWT_SECRET`.

En una base vacía, ejecuta `npm run migrate`. Si ya instalaste T02 con los
scripts oficiales, consulta el procedimiento de adopción antes de migrar.
Después puedes inicializar el administrador con `npm run bootstrap:admin` según
la guía y arrancar con `npm start`. [Guía de instalación B12](docs/tasks/backend/B12.md)

`GET /health` comprueba Express y `GET /health/db` comprueba PostgreSQL.
Para probar la API, consulta [B03](docs/tasks/backend/B03.md) y
[B06](docs/tasks/backend/B06.md).

## Pruebas

Ejecuta `npm test` desde `backend/`. Para las pruebas HTTP contra PostgreSQL real
y las de migraciones, configura `INTEGRATION_DATABASE_URL` y ejecuta
`npm run test:integration`. [Suite de integración B11](docs/tasks/backend/B11.md)
