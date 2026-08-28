import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:new_words/dio_client.dart';
import 'api_response_v2.dart';
import 'input_validator.dart';
import 'service_exceptions.dart';

/// Base class for all API implementations
/// 
/// Provides common HTTP operations with standardized error handling
/// and response parsing. All new API classes should extend this base class.
abstract class BaseApi with InputValidator {
  /// Dio instance for HTTP requests
  late final Dio _dio;

  /// Initialize with DioClient instance or custom Dio for testing
  BaseApi([Dio? customDio]) {
    _dio = customDio ?? DioClient.getInstance();
  }

  /// Perform GET request with standardized response handling
  Future<ApiResponseV2<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      
      return parseResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw ServiceExceptionFactory.fromDioException(e);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Perform POST request with standardized response handling
  Future<ApiResponseV2<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      
      return parseResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw ServiceExceptionFactory.fromDioException(e);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Perform PUT request with standardized response handling
  Future<ApiResponseV2<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      
      return parseResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw ServiceExceptionFactory.fromDioException(e);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Perform DELETE request with standardized response handling
  Future<ApiResponseV2<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      
      return parseResponse<T>(response, fromJson);
    } on DioException catch (e) {
      throw ServiceExceptionFactory.fromDioException(e);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Perform request for void operations (no response data expected)
  Future<ApiResponseV2<void>> requestVoid(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      Response response;
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _dio.get(path, queryParameters: queryParameters, options: options);
          break;
        case 'POST':
          response = await _dio.post(path, data: data, queryParameters: queryParameters, options: options);
          break;
        case 'PUT':
          response = await _dio.put(path, data: data, queryParameters: queryParameters, options: options);
          break;
        case 'DELETE':
          response = await _dio.delete(path, data: data, queryParameters: queryParameters, options: options);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
      
      return parseVoidResponse(response);
    } on DioException catch (e) {
      throw ServiceExceptionFactory.fromDioException(e);
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Parse response data with error handling
  @protected
  ApiResponseV2<T> parseResponse<T>(
    Response response,
    T Function(dynamic json)? fromJson,
  ) {
    try {
      final data = response.data;
      
      if (data is! Map<String, dynamic>) {
        throw DataException.parsing('Expected JSON object but got ${data.runtimeType}');
      }

      if (fromJson != null) {
        return ApiResponseV2<T>.fromJson(
          data, 
          fromJson,
          httpStatusCode: response.statusCode,
        );
      } else {
        // For primitive types or when no parser is provided
        return ApiResponseV2<T>.fromJson(
          data, 
          (json) => json as T,
          httpStatusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ServiceException) {
        rethrow;
      }
      throw DataException.parsing('Failed to parse response: ${e.toString()}', cause: e);
    }
  }

  /// Parse void response (operations that don't return data)
  @protected
  ApiResponseV2<void> parseVoidResponse(Response response) {
    try {
      final data = response.data;
      
      if (data is! Map<String, dynamic>) {
        throw DataException.parsing('Expected JSON object but got ${data.runtimeType}');
      }

      return ApiResponseV2<void>.fromJsonVoid(
        data,
        httpStatusCode: response.statusCode,
      );
    } catch (e) {
      if (e is ServiceException) {
        rethrow;
      }
      throw DataException.parsing('Failed to parse response: ${e.toString()}', cause: e);
    }
  }

  /// Create options with custom timeouts.
  ///
  /// Dio has no per-request connect timeout: its [Options] carries only
  /// [Options.sendTimeout] and [Options.receiveTimeout], and the connect
  /// timeout is read from the client's base options. Configure that one
  /// globally in `DioClient`.
  Options createOptions({
    Duration? sendTimeout,
    Duration? receiveTimeout,
    Map<String, dynamic>? headers,
    String? contentType,
  }) {
    return Options(
      headers: headers,
      contentType: contentType,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  /// Create options for anonymous requests (bypass auth).
  ///
  /// See [createOptions] for why there is no connect timeout here.
  Options createAnonymousOptions({
    Duration? sendTimeout,
    Duration? receiveTimeout,
    Map<String, dynamic>? headers,
    String? contentType,
  }) {
    final finalHeaders = <String, dynamic>{
      'AllowAnonymous': 'true',
      ...?headers,
    };

    return Options(
      headers: finalHeaders,
      contentType: contentType,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  /// Create options for long-running operations.
  ///
  /// See [createOptions] for why there is no connect timeout here.
  Options createLongRunningOptions({
    Duration? sendTimeout = const Duration(minutes: 2),
    Duration? receiveTimeout = const Duration(minutes: 5),
    Map<String, dynamic>? headers,
    String? contentType,
  }) {
    return createOptions(
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
      headers: headers,
      contentType: contentType,
    );
  }
}
