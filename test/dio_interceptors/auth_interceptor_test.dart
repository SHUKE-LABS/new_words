import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/common/foundation/service_exceptions.dart';
import 'package:new_words/dio_interceptors/auth_interceptor.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/utils/app_logger_interface.dart';

import '../mocks/mock_app_logger.dart';

@GenerateMocks([AccountServiceV2])
import 'auth_interceptor_test.mocks.dart';

/// Records which terminal handler call the interceptor made, so a test can
/// assert that a rejected request never also continued down the chain.
class _RecordingHandler extends RequestInterceptorHandler {
  RequestOptions? nextOptions;
  DioException? rejection;

  @override
  void next(RequestOptions requestOptions) {
    nextOptions = requestOptions;
  }

  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {
    rejection = error;
  }
}

void main() {
  group('AuthInterceptor', () {
    late MockAccountServiceV2 mockAccountService;
    late AuthInterceptor interceptor;

    setUp(() {
      mockAccountService = MockAccountServiceV2();
      GetIt.I.registerLazySingleton<AccountServiceV2>(() => mockAccountService);
      GetIt.I.registerLazySingleton<AppLoggerInterface>(() => MockAppLogger());
      interceptor = AuthInterceptor();
    });

    tearDown(() => GetIt.I.reset());

    test('AllowAnonymous request skips token lookup and continues', () async {
      final options = RequestOptions(
        path: '/login',
        headers: {'AllowAnonymous': 'true'},
      );
      final handler = _RecordingHandler();

      interceptor.onRequest(options, handler);
      await pumpEventQueue();

      expect(handler.rejection, isNull);
      expect(handler.nextOptions, same(options));
      expect(options.headers.containsKey('Authorization'), isFalse);
      verifyNever(mockAccountService.getToken());
    });

    test('token present sets the Authorization header', () async {
      when(mockAccountService.getToken()).thenAnswer((_) async => 'abc123');
      final options = RequestOptions(path: '/words');
      final handler = _RecordingHandler();

      interceptor.onRequest(options, handler);
      await pumpEventQueue();

      expect(handler.rejection, isNull);
      expect(handler.nextOptions, same(options));
      expect(options.headers['Authorization'], 'Bearer abc123');
    });

    test('null token continues without an Authorization header', () async {
      when(mockAccountService.getToken()).thenAnswer((_) async => null);
      final options = RequestOptions(path: '/words');
      final handler = _RecordingHandler();

      interceptor.onRequest(options, handler);
      await pumpEventQueue();

      expect(handler.rejection, isNull);
      expect(handler.nextOptions, same(options));
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'token retrieval failure rejects instead of sending unauthenticated',
      () async {
        final cause = Exception('storage unavailable');
        when(mockAccountService.getToken()).thenThrow(cause);
        final options = RequestOptions(path: '/words');
        final handler = _RecordingHandler();

        interceptor.onRequest(options, handler);
        await pumpEventQueue();

        // Never continued down the chain: no unauthenticated request is sent.
        expect(handler.nextOptions, isNull);
        expect(options.headers.containsKey('Authorization'), isFalse);

        final rejection = handler.rejection;
        expect(rejection, isNotNull);
        expect(rejection!.requestOptions, same(options));

        final error = rejection.error;
        expect(error, isA<AuthenticationException>());
        final authError = error as AuthenticationException;
        expect(
          authError.message,
          'Your session is unavailable. Please sign in again.',
        );
        expect(authError.isAuthorizationError, isFalse);
        expect(authError.cause, same(cause));
      },
    );

    test('still rejects when the logger cannot be resolved', () async {
      when(mockAccountService.getToken()).thenThrow(Exception('boom'));
      // Mirrors an un-wired locator: the same condition that breaks token
      // retrieval also breaks logger resolution.
      GetIt.I.unregister<AppLoggerInterface>();
      final options = RequestOptions(path: '/words');
      final handler = _RecordingHandler();

      interceptor.onRequest(options, handler);
      await pumpEventQueue();

      expect(handler.nextOptions, isNull);
      expect(handler.rejection?.error, isA<AuthenticationException>());
    });

    test(
      'rejection maps to the session message, not a generic network error',
      () async {
        when(mockAccountService.getToken()).thenThrow(Exception('boom'));
        final options = RequestOptions(path: '/words');
        final handler = _RecordingHandler();

        interceptor.onRequest(options, handler);
        await pumpEventQueue();

        final mapped = ServiceExceptionFactory.fromDioException(
          handler.rejection!,
        );

        expect(mapped, isA<AuthenticationException>());
        expect(
          mapped.message,
          'Your session is unavailable. Please sign in again.',
        );
      },
    );
  });
}
