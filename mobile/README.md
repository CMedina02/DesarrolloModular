# Inventario Comercial 1.0 — Cliente Flutter (`mobile/`)

Aplicación cliente en Flutter, Dart y Riverpod para **DesarrolloModular**.

## Estructura (F01)

```text
lib/
  main.dart                          # Monta ProviderScope y la app raíz
  app/
    app.dart                         # MaterialApp y tema
    router.dart                      # Rutas y navegación inicial
    theme.dart                       # Tema Material 3
  core/
    config/
      app_config.dart                # Configuración pública por entorno (--dart-define)
      app_config_provider.dart       # Provider Riverpod de AppConfig
  features/
    home/
      presentation/
        home_screen.dart             # Pantalla inicial
        environment_screen.dart      # Vista de configuración activa
```

## Requisitos locales

- Flutter SDK `3.47.4` (Dart `3.13.3`) agregado al `PATH` (por ejemplo `C:\Users\<usuario>\flutter\bin`).
- **Web (Edge):** listo para ejecutar en Windows sin instalar Visual Studio.
- **Windows escritorio:** requiere Visual Studio con la carga de trabajo **Desktop development with C++**.
- **Android:** requiere Android SDK con `cmdline-tools` y licencias aceptadas (`flutter doctor --android-licenses`).

## Comandos de verificación

Desde `mobile/`:

```bash
flutter pub get
flutter analyze
flutter test
```

## Arranque y configuración de URL base

La URL base del backend se configura con `--dart-define=API_BASE_URL=...` (sin modificar el código). Si se omite, usa `http://127.0.0.1:3000`.

### Web (Microsoft Edge) — plataforma comprobada en F01

```bash
flutter run -d edge
```

Cambiando la URL base y el entorno por configuración:

```bash
flutter run -d edge --dart-define=API_BASE_URL=http://192.168.1.50:3000 --dart-define=APP_ENV=qa
```

### Windows escritorio (una vez instalado Visual Studio C++)

```bash
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

> Nota: Las variables `--dart-define` solo deben contener configuración pública de cliente (nunca credenciales, contraseñas ni tokens).
