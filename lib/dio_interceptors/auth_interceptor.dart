import 'package:dio/dio.dart';
import '../common/foundation/service_exceptions.dart';
import '../dependency_injection.dart';
import '../utils/app_logger_interface.dart';
import 'package:new_words/services/account_service_v2.dart';

class AuthInterceptor extends Interceptor {
  // Lazy-load accountService to avoid circular dependency
  AccountServiceV2? _accountService;

  AccountServiceV2 get accountService {
    _accountService ??= locator<AccountServiceV2>();
    return _accountService!;
  }

  AppLoggerInterface? _logger;

  AppLoggerInterface get logger {
    _logger ??= locator<AppLoggerInterface>();
    return _logger!;
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Check if the request requires authentication
    if (options.headers.containsKey('AllowAnonymous')) {
      return handler.next(options);
    }

    final String? token;
    try {
      token = await accountService.getToken();
    } catch (e) {
      // The session could not be read (storage failure, or the account
      // service is not wired up yet). Sending the request anyway would reach
      // the server unauthenticated and surface as a generic "unauthorized",
      // so reject it with a session-specific error instead.
      // The same un-wired-locator condition that breaks token retrieval can
      // also break logger resolution, and the rejection matters more than the
      // log line.
      try {
        logger.e('AuthInterceptor: token retrieval failed: $e');
      } catch (_) {
        // Logging is best-effort here.
      }
      return handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: AuthenticationException(
            'Your session is unavailable. Please sign in again.',
            cause: e,
          ),
        ),
      );
    }

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }
}
