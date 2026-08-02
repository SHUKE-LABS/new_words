import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/entities/page_data.dart';
import 'package:new_words/entities/explanations_response.dart';

/// Modern vocabulary API implementation using BaseApi foundation
/// 
/// This class replaces the old VocabularyApi with standardized error handling,
/// type-safe responses, and centralized constants usage.
class VocabularyApiV2 extends BaseApi {
  /// Create VocabularyApiV2 instance with optional custom Dio for testing
  VocabularyApiV2([super.customDio]);
  /// Add a new word to the vocabulary
  Future<ApiResponseV2<WordExplanation>> addWord(AddWordRequest request) async {
    validateInput({
      'wordText': request.wordText,
      'learningLanguage': request.learningLanguage,
      'explanationLanguage': request.explanationLanguage,
    });

    return await post<WordExplanation>(
      ApiConstants.vocabularyAdd,
      data: request.toJson(),
      fromJson: (json) => WordExplanation.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Add a new word and preserve the complete backend payload for retry logic.
  Future<ApiResponseV2<Map<String, dynamic>>> addWordRaw(
    AddWordRequest request,
  ) async {
    validateInput({
      'wordText': request.wordText,
      'learningLanguage': request.learningLanguage,
      'explanationLanguage': request.explanationLanguage,
    });

    return await post<Map<String, dynamic>>(
      ApiConstants.vocabularyAdd,
      data: request.toJson(),
      fromJson: (json) => Map<String, dynamic>.from(json as Map),
    );
  }

  /// Get paginated list of words
  Future<ApiResponseV2<PageData<WordExplanation>>> listWords(
    int pageNumber,
    int pageSize,
  ) async {
    final paginationParams = processPaginationParams(pageNumber, pageSize);

    return await get<PageData<WordExplanation>>(
      ApiConstants.vocabularyList,
      queryParameters: paginationParams,
      fromJson: (json) => PageData<WordExplanation>.fromJson(
        json as Map<String, dynamic>,
        (wordJson) => WordExplanation.fromJson(wordJson as Map<String, dynamic>),
      ),
    );
  }

  /// Delete a word by ID
  Future<ApiResponseV2<void>> deleteWord(int wordId) async {
    validateNumericField(wordId, 'wordId', min: 1);

    return await requestVoid(
      'DELETE',
      '${ApiConstants.vocabularyDelete}/$wordId',
    );
  }

  /// Refresh explanation for a word
  Future<ApiResponseV2<WordExplanation>> refreshExplanation(int explanationId) async {
    validateNumericField(explanationId, 'explanationId', min: 1);

    return await put<WordExplanation>(
      '${ApiConstants.vocabularyRefreshExplanation}/$explanationId',
      fromJson: (json) => WordExplanation.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get memories (words for spaced repetition)
  Future<ApiResponseV2<List<WordExplanation>>> getMemories(String localTimezone) async {
    validateStringField(
      localTimezone,
      'localTimezone',
      minLength: 1,
      maxLength: 50,
    );

    return await get<List<WordExplanation>>(
      ApiConstants.vocabularyMemories,
      queryParameters: {
        ApiConstants.paramLocalTimezone: localTimezone,
      },
      fromJson: (json) {
        final list = json as List<dynamic>;
        return list
            .map((item) => WordExplanation.fromJson(item as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Get memories for a specific date
  Future<ApiResponseV2<List<WordExplanation>>> getMemoriesOnDate(
    String localTimezone,
    String yyyyMMdd,
  ) async {
    validateStringField(
      localTimezone,
      'localTimezone',
      minLength: 1,
      maxLength: 50,
    );

    validateStringField(
      yyyyMMdd,
      'yyyyMMdd',
      pattern: RegExp(r'^\d{8}$'),
      patternDescription: 'Must be in yyyyMMdd format (e.g., 20241007)',
    );

    return await get<List<WordExplanation>>(
      ApiConstants.vocabularyMemoriesOn,
      queryParameters: {
        ApiConstants.paramLocalTimezone: localTimezone,
        ApiConstants.paramYyyyMMdd: yyyyMMdd,
      },
      fromJson: (json) {
        final list = json as List<dynamic>;
        return list
            .map((item) => WordExplanation.fromJson(item as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Get all explanations for a word
  Future<ApiResponseV2<ExplanationsResponse>> getExplanationsForWord(
    int wordCollectionId,
    String learningLanguage,
    String explanationLanguage,
  ) async {
    validateNumericField(wordCollectionId, 'wordCollectionId', min: 1);
    validateStringField(learningLanguage, 'learningLanguage', minLength: 2, maxLength: 10);
    validateStringField(explanationLanguage, 'explanationLanguage', minLength: 2, maxLength: 10);

    return await get<ExplanationsResponse>(
      '${ApiConstants.vocabularyExplanations}/$wordCollectionId/$learningLanguage/$explanationLanguage',
      queryParameters: {},
      fromJson: (json) => ExplanationsResponse.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Switch user's default explanation
  Future<ApiResponseV2<void>> switchExplanation(
    int wordCollectionId,
    int explanationId,
  ) async {
    validateNumericField(wordCollectionId, 'wordCollectionId', min: 1);
    validateNumericField(explanationId, 'explanationId', min: 1);

    return await requestVoid(
      'PUT',
      '${ApiConstants.vocabularySwitchExplanation}/$wordCollectionId/$explanationId',
    );
  }

  // Helper methods from BaseService for validation
  @override
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
    }
  }

  @override
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

  @override
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

  @override
  Map<String, dynamic> processPaginationParams(
    int pageNumber,
    int pageSize, {
    int maxPageSize = ApiConstants.maxPageSize,
    int minPageSize = ApiConstants.minPageSize,
  }) {
    validateNumericField(pageNumber, 'pageNumber', min: 1);
    validateNumericField(pageSize, 'pageSize', min: minPageSize, max: maxPageSize);

    return {
      ApiConstants.paramPageNumber: pageNumber,
      ApiConstants.paramPageSize: pageSize,
    };
  }
}
