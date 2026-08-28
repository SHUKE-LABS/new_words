import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/app_config.dart';

void main() {
  group('AppConfig.apiBaseUrl', () {
    test('throws when API_BASE_URL is absent', () {
      dotenv.testLoad(fileInput: '');

      expect(() => AppConfig.apiBaseUrl, throwsStateError);
    });

    test('throws when API_BASE_URL is blank', () {
      dotenv.testLoad(fileInput: 'API_BASE_URL=\n');

      expect(() => AppConfig.apiBaseUrl, throwsStateError);
    });

    test('returns the configured value', () {
      dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');

      expect(AppConfig.apiBaseUrl, 'https://test.example.com');
    });
  });
}
