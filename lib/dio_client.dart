import 'package:flutter/foundation.dart';
import 'package:new_words/dio_interceptors/auth_interceptor.dart';
import 'package:dio/dio.dart';

import 'app_config.dart';

class DioClient {
  static Dio? _dio;

  DioClient._internal();

  static Dio getInstance() {
    if (_dio == null) {
      _dio = Dio(); // Create Dio instance if not already created
      _dio!.options.baseUrl = AppConfig.apiBaseUrl;
      _dio!.options.connectTimeout = const Duration(seconds: 30);
      _dio!.options.receiveTimeout = const Duration(seconds: 60);
      // _dio!.options.sendTimeout = const Duration(seconds: 20);

      if (kDebugMode) {
        _dio!.interceptors.add(
          LogInterceptor(requestBody: true, responseBody: true),
        ); // Add logging interceptor
      }
      _dio!.interceptors.add(AuthInterceptor());
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
