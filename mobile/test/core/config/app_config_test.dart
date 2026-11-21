import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_comercial/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('usa valores predeterminados cuando no se pasan overrides', () {
      final config = AppConfig.fromEnvironment();

      expect(config.apiBaseUrl, 'http://127.0.0.1:3000');
      expect(config.environment, 'development');
      expect(config.apiBaseWithPrefix, 'http://127.0.0.1:3000/api/v1');
    });

    test('normaliza barras finales y espacios en la URL base', () {
      final config = AppConfig.fromValues(
        rawApiBaseUrl: '  https://api.ejemplo.local:8443///  ',
        rawEnvironment: ' staging ',
      );

      expect(config.apiBaseUrl, 'https://api.ejemplo.local:8443');
      expect(config.environment, 'staging');
      expect(
        config.apiBaseWithPrefix,
        'https://api.ejemplo.local:8443/api/v1',
      );
    });

    test('evita duplicar el prefijo /api/v1 si la URL ya lo incluye', () {
      final config = AppConfig.fromValues(
        rawApiBaseUrl: 'http://10.0.2.2:3000/api/v1/',
      );

      expect(config.apiBaseUrl, 'http://10.0.2.2:3000');
      expect(config.apiBaseWithPrefix, 'http://10.0.2.2:3000/api/v1');
    });

    test('usa valores por defecto cuando las cadenas están vacías', () {
      final config = AppConfig.fromValues(
        rawApiBaseUrl: '   ',
        rawEnvironment: '',
      );

      expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(config.environment, AppConfig.defaultEnvironment);
    });
  });
}
