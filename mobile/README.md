# Inventario Comercial 1.0 — Cliente Flutter (`mobile/`)

Aplicación cliente en **Flutter, Dart y Riverpod** para **DesarrolloModular** (Core + módulo Inventario Comercial 1.0).

## Estructura del proyecto

```text
lib/
  main.dart                          # Monta ProviderScope y la app raíz
  app/                               # MaterialApp, enrutador y tema Material 3
  core/
    config/                          # AppConfig (--dart-define) y provider
    models/                          # Modelos Dart alineados con OpenAPI 3.1.0
    network/                         # ApiClient (/api/v1 y /health) y traducción de errores
  features/
    auth/                            # Login, /auth/me, token seguro (900 s), AuthGate
    shell/                           # Navegación por rol (PLATFORM_ADMIN, ADMIN, EMPLOYEE)
    admin/                           # Empresas, usuarios y activación de módulos (Core)
    categories/                      # Listado paginado, detalle y CRUD de categorías
    products/                        # Catálogo, esqueleto de carga, filtros y CRUD
    movements/                       # Entradas, salidas, ajustes e historial (ADMIN)
    home/                            # Vista de configuración pública de entorno
test/                                # Pruebas unitarias, de widgets y flujo E2E (F01–F09)
```

## Requisitos locales

- Flutter SDK `3.47.4` (Dart `3.13.3`) en `PATH`.
- **Web (Microsoft Edge):** objetivo comprobado en Windows sin Visual Studio.
- **Windows escritorio (`-d windows`):** requiere Visual Studio con la carga de trabajo **Desktop development with C++**.
- **Android:** requiere Android SDK (`cmdline-tools`) y licencias aceptadas (`flutter doctor --android-licenses`).

## Verificación automatizada (reproducible)

Desde `mobile/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

## Arranque contra backend real

### 1. Entorno backend requerido
- Rama de referencia del backend: `devBackend` (`98d5fab`, B01–B09; requiere **B10** para consultar el historial real `GET /inventory/movements`).
- Base PostgreSQL con esquema T02 (`001_schema.sql`), migración B06 (`004_business_modules.sql`), dos empresas de prueba, módulo `inventory` habilitado y cuentas de prueba (`PLATFORM_ADMIN`, `ADMIN` y `EMPLOYEE`).
- Servidor Express escuchando en `http://127.0.0.1:3000` (o URL compartida acordada con Dev 1).

### 2. Comandos de arranque del cliente

```bash
# Web (Microsoft Edge)
flutter run -d edge --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=APP_ENV=development

# Windows escritorio (requiere Visual Studio C++; sin restricciones CORS)
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=APP_ENV=development

# Emulador Android (apuntando al host local)
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=APP_ENV=development
```

> **Seguridad:** `--dart-define` solo debe incluir configuración pública (URL y entorno). Nunca incluyas credenciales, contraseñas ni tokens en archivos versionados ni en comandos guardados.

## Lista de comprobación manual E2E (F09)

1. **Instalación:** `flutter pub get`, `flutter analyze`, `flutter test` y arranque en el objetivo elegido.
2. **Flujo `ADMIN`:** login → crear categoría → crear producto (`19.90`, stock `0.000`) → entrada → salida → ajuste → consultar historial *(requiere B10)*.
3. **Flujo `EMPLOYEE`:** login → consultar productos activos → registrar entrada/salida → confirmar ausencia de edición, ajuste, empleados e historial.
4. **Aislamiento:** cerrar sesión e ingresar con cuenta de segunda empresa; verificar catálogos y saldos separados y limpieza del estado anterior.
5. **Recuperación:** credenciales inválidas (`401`), sesión vencida (900 s), módulo Inventario deshabilitado (`enabled: false`), pérdida de conexión (confirmación incierta + verificar saldo), stock insuficiente (`409`) y listas vacías.
