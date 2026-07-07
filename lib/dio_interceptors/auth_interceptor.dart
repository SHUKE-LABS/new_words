import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

    try {
      final token = await accountService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      // If AccountServiceV2 is not available yet (during initialization),
      // just continue without auth header
      if (kDebugMode) {
        logger.e(
          'AuthInterceptor: AccountServiceV2 not available yet, continuing without auth: $e',
        );
      }
    }

    return handler.next(options);
  }
}
