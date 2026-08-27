import 'api_response_v2.dart';
import 'input_validator.dart';
import 'service_exceptions.dart';

/// Base class for all service implementations
/// 
/// Provides common patterns for handling API responses, error processing,
/// and data transformation. All new service classes should extend this base class.
abstract class BaseService with InputValidator {
  /// Process API response and extract data or throw service exception
  T processResponse<T>(ApiResponseV2<T> response) {
    if (response.isSuccess && response.data != null) {
      return response.data!;
    } else {
      throw ServiceExceptionFactory.fromApiResponse(
        response.errorMessage,
        response.errorCode,
        response.statusCode,
      );
    }
  }

  /// Process API response for void operations
  void processVoidResponse(ApiResponseV2<void> response) {
    if (!response.isSuccess) {
      throw ServiceExceptionFactory.fromApiResponse(
        response.errorMessage,
        response.errorCode,
        response.statusCode,
      );
    }
  }

  /// Process API response with custom error handling
  T processResponseWithCustomError<T>(
    ApiResponseV2<T> response,
    ServiceException Function(String? message, int? errorCode, int? statusCode) errorFactory,
  ) {
    if (response.isSuccess && response.data != null) {
      return response.data!;
    } else {
      throw errorFactory(response.errorMessage, response.errorCode, response.statusCode);
    }
  }

  /// Safe wrapper for API calls with automatic error conversion
  Future<T> safeApiCall<T>(Future<ApiResponseV2<T>> apiCall) async {
    try {
      final response = await apiCall;
      return processResponse(response);
    } on ServiceException {
      rethrow; // Already a service exception, don't wrap again
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Safe wrapper for void API calls
  Future<void> safeVoidApiCall(Future<ApiResponseV2<void>> apiCall) async {
    try {
      final response = await apiCall;
      processVoidResponse(response);
    } on ServiceException {
      rethrow; // Already a service exception, don't wrap again
    } catch (e) {
      throw ServiceExceptionFactory.fromException(e);
    }
  }

  /// Transform data with error handling
  R transformData<T, R>(
    T data,
    R Function(T data) transformer, {
    String? operationName,
  }) {
    try {
      return transformer(data);
    } catch (e) {
      final operation = operationName ?? 'data transformation';
      throw DataException('Failed to perform $operation: ${e.toString()}', cause: e);
    }
  }

  /// Create standardized error message with context
  String createErrorMessage(String operation, String? details) {
    if (details != null && details.isNotEmpty) {
      return 'Failed to $operation: $details';
    }
    return 'Failed to $operation';
  }

  /// Log service operation (can be overridden by subclasses)
  void logOperation(String operation, {Map<String, dynamic>? parameters}) {
    // Base implementation - can be enhanced with actual logging
    // print('Service operation: $operation ${parameters ?? ''}');
  }

  /// Log service error (can be overridden by subclasses)
  void logError(String operation, ServiceException error) {
    // Base implementation - can be enhanced with actual logging
    // print('Service error in $operation: $error');
  }
}