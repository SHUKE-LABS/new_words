import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/common/constants/api_constants.dart';
import 'package:new_words/dio_interceptors/session_expiry_interceptor.dart';
import 'package:new_words/services/session_expiry_notifier.dart';

import '../mocks/mock_app_logger.dart';

/// Records that the original failure kept travelling down the chain.
class _RecordingHandler extends ErrorInterceptorHandler {
  DioException? forwarded;
  Response<dynamic>? resolved;

  @override
  void next(DioException err) {
    forwarded = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolved = response;
  }
}

void main() {
  group('SessionExpiryInterceptor', () {
    late SessionExpiryNotifier notifier;
    late SessionExpiryInterceptor interceptor;
    late int handlerRuns;

    setUp(() {
      handlerRuns = 0;
      notifier = SessionExpiryNotifier(logger: MockAppLogger());
      notifier.registerHandler(() async => handlerRuns++);
      interceptor = SessionExpiryInterceptor(notifier: notifier);
    });

    DioException errorFor(
      String path, {
      int? statusCode,
      Map<String, dynamic>? headers,
      DioExceptionType type = DioExceptionType.badResponse,
    }) {
      final options = RequestOptions(path: path, headers: headers ?? {});
      return DioException(
        requestOptions: options,
        type: type,
        response:
            statusCode == null
                ? null
                : Response<dynamic>(
                  requestOptions: options,
                  statusCode: statusCode,
                ),
      );
    }

    /// Drains the fire-and-forget notification the interceptor starts.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('401 on a normal endpoint notifies session expiry', () async {
      final handler = _RecordingHandler();

      interceptor.onError(
        errorFor(ApiConstants.vocabularyList, statusCode: 401),
        handler,
      );
      await settle();

      expect(handlerRuns, 1);
      expect(
        handler.forwarded,
        isNotNull,
        reason: 'the original failure must still reach the caller',
      );
    });

    test('401 on the refresh-token endpoint does not notify', () async {
      final handler = _RecordingHandler();

      interceptor.onError(
        errorFor(ApiConstants.accountRefreshToken, statusCode: 401),
        handler,
      );
      await settle();

      expect(handlerRuns, 0);
      expect(handler.forwarded, isNotNull);
    });

    test('401 on login does not notify', () async {
      interceptor.onError(
        errorFor(ApiConstants.authLogin, statusCode: 401),
        _RecordingHandler(),
      );
      await settle();

      expect(handlerRuns, 0);
    });

    test('401 on register does not notify', () async {
      interceptor.onError(
        errorFor(ApiConstants.authRegister, statusCode: 401),
        _RecordingHandler(),
      );
      await settle();

      expect(handlerRuns, 0);
    });

    test('401 carrying AllowAnonymous does not notify', () async {
      interceptor.onError(
        errorFor(
          ApiConstants.vocabularyList,
          statusCode: 401,
          headers: {ApiConstants.headerAllowAnonymous: 'true'},
        ),
        _RecordingHandler(),
      );
      await settle();

      expect(handlerRuns, 0);
    });

    test('an absolute URL for an exempt endpoint is still exempt', () async {
      interceptor.onError(
        errorFor(
          'https://api.example.com${ApiConstants.accountRefreshToken}',
          statusCode: 401,
        ),
        _RecordingHandler(),
      );
      await settle();

      expect(handlerRuns, 0);
    });

    test('a query string does not defeat the exempt-path match', () async {
      interceptor.onError(
        errorFor(
          '${ApiConstants.accountRefreshToken}?retry=1',
          statusCode: 401,
        ),
        _RecordingHandler(),
      );
      await settle();

      expect(handlerRuns, 0);
    });

    test('other error statuses do not notify', () async {
      for (final status in [400, 403, 404, 500]) {
        interceptor.onError(
          errorFor(ApiConstants.vocabularyList, statusCode: status),
          _RecordingHandler(),
        );
      }
      await settle();

      expect(handlerRuns, 0);
    });

    test('a response-less failure does not notify', () async {
      final handler = _RecordingHandler();

      interceptor.onError(
        errorFor(
          ApiConstants.vocabularyList,
          type: DioExceptionType.connectionTimeout,
        ),
        handler,
      );
      await settle();

      expect(handlerRuns, 0);
      expect(handler.forwarded, isNotNull);
    });

    test('concurrent 401s produce a single logout attempt', () async {
      for (var i = 0; i < 5; i++) {
        interceptor.onError(
          errorFor(ApiConstants.vocabularyList, statusCode: 401),
          _RecordingHandler(),
        );
      }
      await settle();

      expect(handlerRuns, 1);
    });

    test('an unresolvable notifier leaves the failure untouched', () async {
      // No notifier injected and no locator registration: the interceptor
      // must degrade to a pass-through rather than throw.
      final handler = _RecordingHandler();

      SessionExpiryInterceptor().onError(
        errorFor(ApiConstants.vocabularyList, statusCode: 401),
        handler,
      );
      await settle();

      expect(handler.forwarded, isNotNull);
    });
  });
}
