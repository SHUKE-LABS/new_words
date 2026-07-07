import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/dio_interceptors/auth_interceptor.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/utils/app_logger_interface.dart';

import '../mocks/mock_app_logger.dart';

@GenerateMocks([AccountServiceV2])
import 'auth_interceptor_test.mocks.dart';

void main() {
  group('AuthInterceptor', () {
    late MockAccountServiceV2 mockAccountService;
    late MockAppLogger mockLogger;

    RequestOptions buildOptions() => RequestOptions(
          path: '/test',
          method: 'GET',
        );

    setUp(() async {
      mockAccountService = MockAccountServiceV2();
      mockLogger = MockAppLogger();

      // Register mocks fresh per test so the interceptor's lazy-resolved
      // service/logger point at this case's instances.
      await GetIt.I.reset();
      GetIt.I.registerLazySingleton<AccountServiceV2>(
        () => mockAccountService,
      );
      GetIt.I.registerLazySingleton<AppLoggerInterface>(() => mockLogger);
    });

    tearDown(() async {
      await GetIt.I.reset();
    });

    test('token unavailable + logger resolves: logs error via AppLogger.e',
        () async {
      when(mockAccountService.getToken()).thenThrow(Exception('boom'));

      final interceptor = AuthInterceptor();
      final handler = RequestInterceptorHandler();
      final options = buildOptions();

      interceptor.onRequest(options, handler);
      // handler.future resolves when onRequest's catch block calls handler.next.
      // ignore: invalid_use_of_protected_member
      final state = await handler.future;

      // The catch block logged via the registered logger, then proceeded.
      expect(mockLogger.errorLogs, hasLength(1));
      expect(mockLogger.errorLogs.single, contains('AuthInterceptor'));
      expect(mockLogger.errorLogs.single, contains('boom'));
      // Proceeded to next interceptor with the original options.
      expect(state.data, same(options));
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('logger resolution throws (GetIt not registered): silently proceeds',
        () async {
      // Drop the logger registration so locator<AppLoggerInterface>() throws.
      // The interceptor must not crash and must still call handler.next.
      await GetIt.I.unregister<AppLoggerInterface>();
      when(mockAccountService.getToken()).thenThrow(Exception('service down'));

      final interceptor = AuthInterceptor();
      final handler = RequestInterceptorHandler();
      final options = buildOptions();

      interceptor.onRequest(options, handler);
      // ignore: invalid_use_of_protected_member
      final state = await handler.future;

      // No logger was registered; the interceptor must still call handler.next.
      expect(state.data, same(options));
      expect(options.headers.containsKey('Authorization'), isFalse);
    });
  });
}
