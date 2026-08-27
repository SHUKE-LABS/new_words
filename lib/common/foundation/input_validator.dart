import 'service_exceptions.dart';

/// Shared input validation helpers for API and service layers
///
/// Mixed into [BaseApi] and [BaseService] so both layers validate inputs
/// with a single implementation instead of parallel copies.
mixin InputValidator {
  /// Validate input data before API calls
  void validateInput(Map<String, dynamic> validations) {
    for (final entry in validations.entries) {
      final field = entry.key;
      final value = entry.value;

      if (value == null) {
        throw DataException.validation(field, 'Field is required');
      }

      if (value is String && value.trim().isEmpty) {
        throw DataException.validation(field, 'Field cannot be empty');
      }

      if (value is List && value.isEmpty) {
        throw DataException.validation(field, 'List cannot be empty');
      }
    }
  }

  /// Validate string field with custom rules
  void validateStringField(
    String? value,
    String fieldName, {
    int? minLength,
    int? maxLength,
    bool required = true,
    Pattern? pattern,
    String? patternDescription,
  }) {
    if (required && (value == null || value.trim().isEmpty)) {
      throw DataException.validation(fieldName, 'Field is required');
    }

    if (value != null && value.isNotEmpty) {
      if (minLength != null && value.length < minLength) {
        throw DataException.validation(fieldName, 'Must be at least $minLength characters');
      }

      if (maxLength != null && value.length > maxLength) {
        throw DataException.validation(fieldName, 'Must be no more than $maxLength characters');
      }

      if (pattern != null) {
        bool matches = false;
        if (pattern is RegExp) {
          matches = pattern.hasMatch(value);
        } else {
          matches = pattern.allMatches(value).isNotEmpty;
        }

        if (!matches) {
          final description = patternDescription ?? 'Invalid format';
          throw DataException.validation(fieldName, description);
        }
      }
    }
  }

  /// Validate numeric field with range checks
  void validateNumericField(
    num? value,
    String fieldName, {
    num? min,
    num? max,
    bool required = true,
  }) {
    if (required && value == null) {
      throw DataException.validation(fieldName, 'Field is required');
    }

    if (value != null) {
      if (min != null && value < min) {
        throw DataException.validation(fieldName, 'Must be at least $min');
      }

      if (max != null && value > max) {
        throw DataException.validation(fieldName, 'Must be no more than $max');
      }
    }
  }

  /// Handle pagination parameters with validation
  Map<String, dynamic> processPaginationParams(
    int pageNumber,
    int pageSize, {
    int maxPageSize = 100,
    int minPageSize = 1,
  }) {
    validateNumericField(pageNumber, 'pageNumber', min: 1);
    validateNumericField(pageSize, 'pageSize', min: minPageSize, max: maxPageSize);

    return {
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    };
  }
}
