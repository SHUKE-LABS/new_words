import 'package:dio/dio.dart';

/// Base exception for all service layer errors
/// 
/// This provides a standardized way to handle different types of errors
/// that can occur in the service layer, replacing the current ApiException.
abstract class ServiceException implements Exception {
  /// Human-readable error message
  final String message;
  
  /// Optional underlying cause
  final dynamic cause;
  
  /// Optional error code from backend
  final int? errorCode;

  const ServiceException(this.message, {this.cause, this.errorCode});

  @override
  String toString() => 'ServiceException: $message';
}

/// Network-related errors (connection, timeout, etc.)
class NetworkException extends ServiceException {
  /// HTTP status code if available
  final int? statusCode;

  const NetworkException(
    super.message, {
    super.cause,
    this.statusCode,
  });

  factory NetworkException.fromDioException(DioException dioException) {
    String message;
    int? statusCode = dioException.response?.statusCode;

    switch (dioException.type) {
      case DioExceptionType.connectionTimeout:
        message = 'Connection timeout. Please check your internet connection.';
        break;
      case DioExceptionType.sendTimeout:
        message = 'Request timeout. Please try again.';
        break;
      case DioExceptionType.receiveTimeout:
        message = 'Response timeout. Please try again.';
        break;
      case DioExceptionType.badResponse:
        message = 'Server error (${statusCode ?? 'unknown'}). Please try again.';
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        message = 'Connection error. Please check your internet connection.';
        break;
      case DioExceptionType.badCertificate:
        message = 'Certificate error. Please contact support.';
        break;
      default:
        message = 'Network error: ${dioException.message ?? 'Unknown error'}';
    }

    return NetworkException(
      message,
      cause: dioException,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => 'NetworkException: $message (Status: $statusCode)';
}

/// API-specific business logic errors
class ApiBusinessException extends ServiceException {
  /// Backend error code
  final int? backendErrorCode;

  const ApiBusinessException(
    super.message, {
    super.cause,
    this.backendErrorCode,
  }) : super(errorCode: backendErrorCode);

  @override
  String toString() => 'ApiBusinessException: $message (Code: $backendErrorCode)';
}

/// Authentication/authorization errors
class AuthenticationException extends ServiceException {
  /// Whether this is an authorization (403) vs authentication (401) error
  final bool isAuthorizationError;

  const AuthenticationException(
    super.message, {
    super.cause,
    super.errorCode,
    this.isAuthorizationError = false,
  });

  factory AuthenticationException.unauthorized() {
    return const AuthenticationException(
      'Authentication required. Please log in again.',
      isAuthorizationError: false,
    );
  }

  factory AuthenticationException.forbidden() {
    return const AuthenticationException(
      'Access denied. You do not have permission to perform this action.',
      isAuthorizationError: true,
    );
  }

  @override
  String toString() {
    final type = isAuthorizationError ? 'Authorization' : 'Authentication';
    return 'AuthenticationException ($type): $message';
  }
}

/// Data validation or parsing errors
class DataException extends ServiceException {
  /// The field that caused the validation error, if applicable
  final String? field;

  const DataException(
    super.message, {
    super.cause,
    super.errorCode,
    this.field,
  });

  factory DataException.validation(String field, String message) {
    return DataException(
      'Validation error for $field: $message',
      field: field,
    );
  }

  factory DataException.parsing(String message, {dynamic cause}) {
    return DataException(
      'Data parsing error: $message',
      cause: cause,
    );
  }

  @override
  String toString() {
    if (field != null) {
      return 'DataException ($field): $message';
    }
    return 'DataException: $message';
  }
}

/// Server-side errors (5xx responses)
class ServerException extends ServiceException {
  /// HTTP status code
  final int statusCode;

  const ServerException(
    super.message, {
    super.cause,
    super.errorCode,
    required this.statusCode,
  });

  factory ServerException.internal() {
    return const ServerException(
      'Internal server error. Please try again later.',
      statusCode: 500,
    );
  }

  factory ServerException.maintenance() {
    return const ServerException(
      'Server is under maintenance. Please try again later.',
      statusCode: 503,
    );
  }

  @override
  String toString() => 'ServerException ($statusCode): $message';
}

/// Utility class for converting various errors to ServiceExceptions
class ServiceExceptionFactory {
  static ServiceException fromDioException(DioException dioException) {
    // An already-typed cause (e.g. thrown by an interceptor) carries a more
    // specific message than status/network normalization can produce, so it
    // must pass through ahead of both.
    final cause = dioException.error;
    if (cause is ServiceException) {
      return cause;
    }

    final statusCode = dioException.response?.statusCode;

    // Handle specific HTTP status codes
    if (statusCode != null) {
      switch (statusCode) {
        case 401:
          return AuthenticationException.unauthorized();
        case 403:
          return AuthenticationException.forbidden();
        case >= 500:
          return ServerException(
            'Server error ($statusCode). Please try again later.',
            statusCode: statusCode,
            cause: dioException,
          );
        case >= 400:
          // Extract error message from response body if available
          String errorMessage = 'Client error ($statusCode)';
          int? errorCode;
          
          if (dioException.response?.data is Map<String, dynamic>) {
            final data = dioException.response!.data as Map<String, dynamic>;
            errorMessage = data['message'] as String? ?? errorMessage;
            errorCode = data['errorCode'] as int?;
          }
          
          return ApiBusinessException(
            errorMessage,
            backendErrorCode: errorCode,
          );
      }
    }

    // Handle network-level errors
    return NetworkException.fromDioException(dioException);
  }

  static ServiceException fromApiResponse(
    String? errorMessage,
    int? errorCode,
    int? statusCode,
  ) {
    final message = errorMessage ?? 'Unknown API error';

    // Determine exception type based on status code or error code
    if (statusCode != null) {
      switch (statusCode) {
        case 401:
          return AuthenticationException.unauthorized();
        case 403:
          return AuthenticationException.forbidden();
        case >= 500:
          return ServerException(message, statusCode: statusCode);
        case >= 400:
          return ApiBusinessException(message, backendErrorCode: errorCode);
      }
    }

    // Default to business exception
    return ApiBusinessException(message, backendErrorCode: errorCode);
  }

  static ServiceException fromException(dynamic exception) {
    if (exception is ServiceException) {
      return exception;
    }
    
    if (exception is DioException) {
      return fromDioException(exception);
    }

    // Generic exception wrapper
    return DataException(
      'Unexpected error: ${exception.toString()}',
      cause: exception,
    );
  }
}