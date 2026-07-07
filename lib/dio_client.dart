import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:new_words/app_config.dart';
import 'package:new_words/dependency_injection.dart';
import 'package:new_words/dio_interceptors/auth_interceptor.dart';
import 'package:new_words/utils/app_logger_interface.dart';

class DioClient {
  static Dio? _dio;

  DioClient._internal();

  /// Test-only reset hook. The Flutter test runner shares one isolate, so
  /// the cached static singleton must be cleared between cases to exercise
  /// fresh interceptor registration.
  @visibleForTesting
  static void resetForTest() {
    _dio = null;
  }

  static Dio getInstance() {
    if (_dio == null) {
      _dio = Dio(); // Create Dio instance if not already created
      _dio!.options.baseUrl = AppConfig.apiBaseUrl;
      _dio!.options.connectTimeout = const Duration(seconds: 30);
      _dio!.options.receiveTimeout = const Duration(seconds: 60);
      // _dio!.options.sendTimeout = const Duration(seconds: 20);

      // Register AuthInterceptor FIRST so HttpLogInterceptor (registered after)
      // observes the real outgoing `Authorization` header it injects.
      _dio!.interceptors.add(AuthInterceptor());
      if (_shouldRegisterHttpLog()) {
        _dio!.interceptors.add(HttpLogInterceptor());
      }
      _dio!.interceptors.add(
        InterceptorsWrapper(
          onRequest: (
            RequestOptions options,
            RequestInterceptorHandler handler,
          ) {
            options.contentType = 'application/json';
            return handler.next(options);
          },
          onResponse: (Response response, ResponseInterceptorHandler handler) {
            // Handle global response data here if needed
            return handler.next(response);
          },
          onError: (DioException e, ErrorInterceptorHandler handler) {
            // Handle global error here
            // AppLogger.e(e.toString());
            return handler.next(e);
          },
        ),
      );
    }
    return _dio!;
  }
}

/// Test override for [_shouldRegisterHttpLog]. When non-null, bypasses both
/// `kDebugMode` and `AppConfig.debugging` checks. Production code never sets
/// this; tests flip it to exercise the gate.
@visibleForTesting
bool? httpLogGateOverride;

bool _shouldRegisterHttpLog() {
  if (httpLogGateOverride != null) return httpLogGateOverride!;
  if (!kDebugMode) return false;
  if (!AppConfig.debugging) return false;
  return true;
}

/// Project-local replacement for Dio's built-in `LogInterceptor` that:
///   * routes through `AppLogger` (no `print`),
///   * redacts `Authorization`, `password`, and token keys in headers/bodies,
///   * never logs raw request bodies (only shape/headers on request).
///
/// Interceptor order matters: must be registered **after** [AuthInterceptor]
/// so the `Authorization` redaction sees the real outgoing token.
class HttpLogInterceptor extends Interceptor {
  static const _sensitiveKeys = <String>{
    'password',
    'token',
    'access_token',
    'refresh_token',
    'newpassword',
    'currentpassword',
  };

  final AppLoggerInterface? _logger;

  HttpLogInterceptor({AppLoggerInterface? logger}) : _logger = logger;

  AppLoggerInterface? get _resolvedLogger => _logger ?? _tryResolve();

  AppLoggerInterface? _tryResolve() {
    try {
      return locator<AppLoggerInterface>();
    } catch (_) {
      return null;
    }
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final logger = _resolvedLogger;
    if (logger != null) {
      final redactedHeaders = _redactHeaders(options.headers);
      logger.d(
        'HTTP request: ${options.method} ${options.uri} '
        'headers=$redactedHeaders',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    final logger = _resolvedLogger;
    if (logger != null) {
      logger.d(
        'HTTP response: ${response.statusCode} ${response.requestOptions.uri} '
        'body=${_summarizeBody(response.data)}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final logger = _resolvedLogger;
    if (logger != null) {
      logger.e(
        'HTTP error: ${err.response?.statusCode} ${err.requestOptions.uri} '
        'message=${err.message}',
      );
    }
    handler.next(err);
  }

  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
    final result = <String, dynamic>{};
    headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'authorization') {
        result[key] = '***';
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// Returns a redacted copy for JSON shapes, or `<shape>(<bytes>)` for
  /// anything else. Never returns the raw request body.
  String _summarizeBody(dynamic body) {
    if (body == null) return 'null';
    if (body is Map<String, dynamic>) {
      return _redactMap(body).toString();
    }
    if (body is List) {
      return body.map((e) {
        if (e is Map<String, dynamic>) return _redactMap(e);
        return e;
      }).toString();
    }
    final raw = body.toString();
    return '${body.runtimeType}(${raw.length})';
  }
}

/// Recursively redact sensitive values. Returns a copy.
dynamic _redactBody(dynamic body) {
  if (body is Map<String, dynamic>) return _redactMap(body);
  if (body is List) {
    return body.map((e) => _redactBody(e)).toList();
  }
  return body;
}

Map<String, dynamic> _redactMap(Map<String, dynamic> input) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    if (HttpLogInterceptor._sensitiveKeys.contains(key.toLowerCase())) {
      result[key] = '***';
    } else {
      result[key] = _redactBody(value);
    }
  });
  return result;
}
