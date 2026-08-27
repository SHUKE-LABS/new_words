import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:new_words/common/foundation/service_exceptions.dart';

void main() {
  group('ServiceException hierarchy', () {
    group('NetworkException', () {
      test('creates from connection timeout', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final networkException = NetworkException.fromDioException(dioException);

        expect(networkException.message, contains('Connection timeout'));
        expect(networkException.cause, equals(dioException));
        expect(networkException.statusCode, isNull);
      });

      test('creates from bad response with status code', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );

        final networkException = NetworkException.fromDioException(dioException);

        expect(networkException.message, contains('Server error (500)'));
        expect(networkException.statusCode, equals(500));
      });

      test('creates from connection error', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        final networkException = NetworkException.fromDioException(dioException);

        expect(networkException.message, contains('Connection error'));
      });

      test('toString includes status code when available', () {
        const networkException = NetworkException(
          'Test error',
          statusCode: 404,
        );

        final result = networkException.toString();

        expect(result, contains('NetworkException'));
        expect(result, contains('Test error'));
        expect(result, contains('404'));
      });
    });

    group('ApiBusinessException', () {
      test('creates with backend error code', () {
        const exception = ApiBusinessException(
          'Business logic error',
          backendErrorCode: 1001,
        );

        expect(exception.message, equals('Business logic error'));
        expect(exception.backendErrorCode, equals(1001));
        expect(exception.errorCode, equals(1001));
      });

      test('toString includes backend error code', () {
        const exception = ApiBusinessException(
          'Validation failed',
          backendErrorCode: 2001,
        );

        final result = exception.toString();

        expect(result, contains('ApiBusinessException'));
        expect(result, contains('Validation failed'));
        expect(result, contains('2001'));
      });
    });

    group('AuthenticationException', () {
      test('creates unauthorized exception', () {
        final exception = AuthenticationException.unauthorized();

        expect(exception.message, contains('Authentication required'));
        expect(exception.isAuthorizationError, isFalse);
      });

      test('creates forbidden exception', () {
        final exception = AuthenticationException.forbidden();

        expect(exception.message, contains('Access denied'));
        expect(exception.isAuthorizationError, isTrue);
      });

      test('toString distinguishes between auth and authz', () {
        final authException = AuthenticationException.unauthorized();
        final authzException = AuthenticationException.forbidden();

        expect(authException.toString(), contains('Authentication'));
        expect(authzException.toString(), contains('Authorization'));
      });
    });

    group('DataException', () {
      test('creates validation exception with field', () {
        final exception = DataException.validation('email', 'Invalid format');

        expect(exception.message, contains('Validation error for email'));
        expect(exception.message, contains('Invalid format'));
        expect(exception.field, equals('email'));
      });

      test('creates parsing exception with cause', () {
        final cause = FormatException('Invalid JSON');
        final exception = DataException.parsing('JSON parse error', cause: cause);

        expect(exception.message, contains('Data parsing error'));
        expect(exception.message, contains('JSON parse error'));
        expect(exception.cause, equals(cause));
        expect(exception.field, isNull);
      });

      test('toString includes field when available', () {
        final exception = DataException.validation('username', 'Too short');

        final result = exception.toString();

        expect(result, contains('DataException (username)'));
        expect(result, contains('Too short'));
      });

      test('toString without field', () {
        final exception = DataException.parsing('Invalid format');

        final result = exception.toString();

        expect(result, contains('DataException'));
        expect(result, isNot(contains('(')));
      });
    });

    group('ServerException', () {
      test('creates internal server error', () {
        final exception = ServerException.internal();

        expect(exception.message, contains('Internal server error'));
        expect(exception.statusCode, equals(500));
      });

      test('creates maintenance error', () {
        final exception = ServerException.maintenance();

        expect(exception.message, contains('maintenance'));
        expect(exception.statusCode, equals(503));
      });

      test('toString includes status code', () {
        final exception = ServerException.internal();

        final result = exception.toString();

        expect(result, contains('ServerException (500)'));
      });
    });
  });

  group('ServiceExceptionFactory', () {
    group('fromDioException', () {
      test('passes a typed ServiceException cause through unchanged', () {
        const cause = AuthenticationException('Session gone. Sign in again.');
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.unknown,
          error: cause,
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, same(cause));
      });

      test('typed cause wins over status-code normalization', () {
        const cause = AuthenticationException('Session gone. Sign in again.');
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          error: cause,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, same(cause));
      });

      test('converts 401 to AuthenticationException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 401,
          ),
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, isA<AuthenticationException>());
        expect((result as AuthenticationException).isAuthorizationError, isFalse);
      });

      test('converts 403 to AuthenticationException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 403,
          ),
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, isA<AuthenticationException>());
        expect((result as AuthenticationException).isAuthorizationError, isTrue);
      });

      test('converts 5xx to ServerException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 502,
          ),
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, isA<ServerException>());
        expect((result as ServerException).statusCode, equals(502));
      });

      test('converts network errors to NetworkException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = ServiceExceptionFactory.fromDioException(dioException);

        expect(result, isA<NetworkException>());
      });
    });

    group('fromApiResponse', () {
      test('converts 401 status to AuthenticationException', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          'Unauthorized',
          null,
          401,
        );

        expect(result, isA<AuthenticationException>());
      });

      test('converts 403 status to AuthenticationException', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          'Forbidden',
          null,
          403,
        );

        expect(result, isA<AuthenticationException>());
      });

      test('converts 5xx status to ServerException', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          'Server error',
          1001,
          500,
        );

        expect(result, isA<ServerException>());
        expect((result as ServerException).statusCode, equals(500));
      });

      test('converts 4xx status to ApiBusinessException', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          'Validation failed',
          2001,
          400,
        );

        expect(result, isA<ApiBusinessException>());
        expect((result as ApiBusinessException).backendErrorCode, equals(2001));
      });

      test('defaults to ApiBusinessException when no status code', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          'Unknown error',
          3001,
          null,
        );

        expect(result, isA<ApiBusinessException>());
        expect((result as ApiBusinessException).backendErrorCode, equals(3001));
      });

      test('handles null error message', () {
        final result = ServiceExceptionFactory.fromApiResponse(
          null,
          null,
          400,
        );

        expect(result.message, equals('Unknown API error'));
      });
    });

    group('fromException', () {
      test('returns ServiceException as-is', () {
        const originalException = ApiBusinessException('Original error');

        final result = ServiceExceptionFactory.fromException(originalException);

        expect(result, equals(originalException));
      });

      test('converts DioException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = ServiceExceptionFactory.fromException(dioException);

        expect(result, isA<NetworkException>());
      });

      test('wraps generic exception as DataException', () {
        final genericException = Exception('Generic error');

        final result = ServiceExceptionFactory.fromException(genericException);

        expect(result, isA<DataException>());
        expect(result.message, contains('Unexpected error'));
        expect(result.cause, equals(genericException));
      });
    });
  });
}