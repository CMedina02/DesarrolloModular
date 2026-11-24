# Desarrollo Modular

Repositorio para una plataforma modular orientada a pequeños comercios. El primer módulo es Inventario Comercial 1.0.

## Estructura

- `backend/database/`: esquema PostgreSQL, datos de demostración y pruebas de integridad de T02.
- `backend/src/`: servidor Express, configuración y acceso compartido a PostgreSQL.
- `mobile/`: aplicación Flutter de Inventario Comercial para web, con proyecto Android.
- `docs/`: documentación del proyecto.

## Arranque web local

Prepara primero PostgreSQL y la configuración del backend con la guía de
instalación de abajo. Desde la raíz del repositorio, compila el cliente y
arranca Express en modo web.

```bash
(cd mobile && flutter pub get && flutter build web --no-web-resources-cdn)
(cd backend && npm run start:web)
```

Abre [la aplicación](http://127.0.0.1:3000). Express sirve Flutter y la API
desde la misma dirección. Para publicar este modo web, usa HTTPS en el
dominio público y conserva la API bajo ese mismo origen.

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
