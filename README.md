# Desarrollo Modular

Repositorio para una plataforma modular orientada a pequeños comercios. El primer módulo es Inventario Comercial 1.0.

## Estructura

- `backend/database/`: esquema PostgreSQL, datos de demostración y pruebas de integridad de T02.
- `backend/src/`: servidor Express, configuración y acceso compartido a PostgreSQL.
- `mobile/`: reservado para la aplicación Flutter de etapas posteriores.
- `docs/`: documentación del proyecto.

Consulta [`backend/database/README.md`](backend/database/README.md) para preparar y validar la base local. Los datos de demostración son solo para desarrollo.

## Arranque del backend

Desde `backend/`, instala con `npm ci` y configura `.env` a partir de
`.env.example` con tu conexión PostgreSQL local y una clave `JWT_SECRET`. Ejecuta `npm start` para
arrancar Express y `npm test` para correr las pruebas automatizadas. Requiere
Node.js 22.21 o posterior.

`GET /health` comprueba el servidor y `GET /health/db` comprueba PostgreSQL.
Consulta [B02](docs/tasks/backend/B02.md) para ver la configuración y las pruebas.

Consulta [B03](docs/tasks/backend/B03.md) para generar la clave, crear el primer
administrador y probar `POST /api/v1/auth/login` y `GET /api/v1/auth/me`.
