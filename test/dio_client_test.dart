import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/dio_client.dart';
import 'package:new_words/dio_interceptors/auth_interceptor.dart';
import 'package:new_words/utils/app_logger_interface.dart';

import 'mocks/mock_app_logger.dart';

void main() {
  group('DioClient', () {
    late MockAppLogger mockLogger;
    final originalGate = httpLogGateOverride;

    setUpAll(() {
      // AppConfig.apiBaseUrl reads from dotenv; initialize with a stub URL.
      dotenv.testLoad(fileInput: '''
API_BASE_URL=https://test.example.com
''');
    });

    setUp(() {
      // Register a fresh mock logger in the locator so HttpLogInterceptor can
      // resolve one. resetForTest clears the cached Dio so each case exercises
      // a fresh interceptor chain.
      mockLogger = MockAppLogger();
      if (GetIt.I.isRegistered<AppLoggerInterface>()) {
        GetIt.I.unregister<AppLoggerInterface>();
      }
      GetIt.I.registerLazySingleton<AppLoggerInterface>(() => mockLogger);
    });

    tearDown(() {
      httpLogGateOverride = originalGate;
      DioClient.resetForTest();
      GetIt.I.reset();
    });

    test('release build: gate is false → no HttpLogInterceptor registered', () {
      httpLogGateOverride = false;
      final dio = DioClient.getInstance();

      expect(
        dio.interceptors.whereType<HttpLogInterceptor>().toList(),
        isEmpty,
      );
    });

    test('debug build, DEBUGGING=0: gate is false → no HttpLogInterceptor', () {
      httpLogGateOverride = false;
      final dio = DioClient.getInstance();

      expect(
        dio.interceptors.whereType<HttpLogInterceptor>().toList(),
        isEmpty,
      );
    });

    test('debug build, DEBUGGING=1: gate is true → exactly one HttpLogInterceptor', () {
      httpLogGateOverride = true;
      final dio = DioClient.getInstance();

      final logInterceptors =
          dio.interceptors.whereType<HttpLogInterceptor>().toList();
      expect(logInterceptors, hasLength(1));
    });

    test('interceptor order: AuthInterceptor registers before HttpLogInterceptor', () {
      httpLogGateOverride = true;
      final dio = DioClient.getInstance();

      // Dio may inject internal interceptors (e.g. ImplyContentTypeInterceptor)
      // at index 0; assert only that AuthInterceptor precedes HttpLogInterceptor
      // so the log interceptor sees the header AuthInterceptor injects.
      final authIdx = dio.interceptors
          .toList()
          .indexWhere((i) => i is AuthInterceptor);
      final logIdx = dio.interceptors
          .toList()
          .indexWhere((i) => i is HttpLogInterceptor);
      expect(authIdx, isNonNegative);
      expect(logIdx, isNonNegative);
      expect(authIdx, lessThan(logIdx));
    });

    test('Authorization header is redacted in request log', () async {
      httpLogGateOverride = true;
      final dio = DioClient.getInstance();
      final logInterceptor = dio.interceptors
          .whereType<HttpLogInterceptor>()
          .single;

      final options = RequestOptions(
        path: '/test',
        method: 'GET',
        headers: {'Authorization': 'Bearer abc123'},
      );
      final handler = RequestInterceptorHandler();

      // Manually populate the header as AuthInterceptor would have.
      options.headers['Authorization'] = 'Bearer abc123';

      logInterceptor.onRequest(options, handler);
      // onRequest calls handler.next synchronously; logger has logged by now.

      final requestLogs =
          mockLogger.debugLogs.where((l) => l.contains('HTTP request')).toList();
      expect(requestLogs, hasLength(1));
      expect(requestLogs.single, contains('Authorization: ***'));
      expect(requestLogs.single, isNot(contains('abc123')));
    });

    test('response body redaction strips password and token values', () async {
      httpLogGateOverride = true;
      final dio = DioClient.getInstance();
      final logInterceptor = dio.interceptors
          .whereType<HttpLogInterceptor>()
          .single;

      final options = RequestOptions(path: '/login', method: 'POST');
      final response = Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'successful': true,
          'data': {
            'token': 'plaintext-jwt-abc',
            'refreshToken': 'refresh-abc',
            'user': {
              'email': 'user@example.com',
              'password': 'plaintext-pw',
            },
          },
        },
      );
      final handler = ResponseInterceptorHandler();

      logInterceptor.onResponse(response, handler);
      // onResponse calls handler.next synchronously; logger has logged by now.

      final responseLogs = mockLogger.debugLogs
          .where((l) => l.contains('HTTP response'))
          .toList();
      expect(responseLogs, hasLength(1));
      final log = responseLogs.single;
      expect(log, contains('***'));
      expect(log, isNot(contains('plaintext-jwt-abc')));
      expect(log, isNot(contains('plaintext-pw')));
      expect(log, contains('user@example.com'));
    });
  });
}
