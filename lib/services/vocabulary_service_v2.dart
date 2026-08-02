import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/apis/vocabulary_api_v2.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/entities/page_data.dart';
import 'package:new_words/entities/explanations_response.dart';

/// Modern vocabulary service implementation using BaseService foundation
/// 
/// This class replaces the old VocabularyService with standardized error handling,
/// validation, and cleaner business logic separation.
class VocabularyServiceV2 extends BaseService {
  final VocabularyApiV2 _vocabularyApi;

  VocabularyServiceV2(this._vocabularyApi);

  /// Add a new word to the vocabulary
  Future<WordExplanation> addWord(AddWordRequest request) async {
    logOperation('addWord', parameters: {
      'wordText': request.wordText.length > 10 
          ? request.wordText.substring(0, 10) 
          : request.wordText, // Log only first 10 chars for privacy
    });

    try {
      // Validate input using BaseService validation
      validateInput({
        'wordText': request.wordText,
        'learningLanguage': request.learningLanguage,
        'explanationLanguage': request.explanationLanguage,
      });

      validateStringField(
        request.wordText,
        'wordText',
        minLength: AppConstants.minWordLength,
        maxLength: AppConstants.maxWordLength,
        pattern: RegExp(AppConstants.wordRegex, unicode: true),
        patternDescription: 'Word must contain only letters, spaces, hyphens, and apostrophes',
      );

      validateStringField(
        request.learningLanguage,
        'learningLanguage',
        minLength: 2,
        maxLength: 10,
      );

      validateStringField(
        request.explanationLanguage,
        'explanationLanguage',
        minLength: 2,
        maxLength: 10,
      );

      final response = await _vocabularyApi.addWord(request);
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('addWord', error);
      throw error;
    }
  }

  /// Add a new word while preserving the complete backend payload.
  Future<Map<String, dynamic>> addWordRaw(AddWordRequest request) async {
    logOperation('addWordRaw', parameters: {
      'wordText': request.wordText.length > 10
          ? request.wordText.substring(0, 10)
          : request.wordText,
    });

    try {
      validateInput({
        'wordText': request.wordText,
        'learningLanguage': request.learningLanguage,
        'explanationLanguage': request.explanationLanguage,
      });

      validateStringField(
        request.wordText,
        'wordText',
        minLength: AppConstants.minWordLength,
        maxLength: AppConstants.maxWordLength,
        pattern: RegExp(AppConstants.wordRegex, unicode: true),
        patternDescription:
            'Word must contain only letters, spaces, hyphens, and apostrophes',
      );

      validateStringField(
        request.learningLanguage,
        'learningLanguage',
        minLength: 2,
        maxLength: 10,
      );

      validateStringField(
        request.explanationLanguage,
        'explanationLanguage',
        minLength: 2,
        maxLength: 10,
      );

      final response = await _vocabularyApi.addWordRaw(request);
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('addWordRaw', error);
      throw error;
    }
  }

  /// Get paginated list of words
  Future<PageData<WordExplanation>> listWords(
    int pageNumber,
    int pageSize,
  ) async {
    logOperation('listWords', parameters: {
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });

    try {
      // Use BaseService pagination validation
      final paginationParams = processPaginationParams(
        pageNumber,
        pageSize,
        maxPageSize: AppConstants.maxWordsPerPage,
      );

      final response = await _vocabularyApi.listWords(
        paginationParams[ApiConstants.paramPageNumber] as int,
        paginationParams[ApiConstants.paramPageSize] as int,
      );
      
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('listWords', error);
      throw error;
    }
  }

  /// Delete a word by ID
  Future<void> deleteWord(int wordId) async {
    logOperation('deleteWord', parameters: {'wordId': wordId});

    try {
      validateNumericField(wordId, 'wordId', min: 1);

      final response = await _vocabularyApi.deleteWord(wordId);
      processVoidResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('deleteWord', error);
      throw error;
    }
  }

  /// Refresh explanation for a word
  Future<RefreshExplanationResult> refreshExplanation(
    WordExplanation explanation,
  ) async {
    logOperation('refreshExplanation', parameters: {
      'explanationId': explanation.id,
    });

    try {
      validateInput({'explanation': explanation});
      validateNumericField(explanation.id, 'explanationId', min: 1);

      final response = await _vocabularyApi.refreshExplanation(explanation.id);
      
      if (response.isSuccess && response.data != null) {
        return RefreshExplanationResult.updated(response.data!);
      } else {
        // Handle specific case where no refresh was needed
        // This maintains compatibility with existing logic
        if (response.isError && response.errorCode != null && response.errorCode! > 0) {
          return RefreshExplanationResult.noUpdate(
            response.errorMessage ?? 'No update needed',
          );
        }
        
        // For other errors, let the standard error handling take over
        return RefreshExplanationResult.updated(processResponse(response));
      }
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('refreshExplanation', error);
      
      // For backward compatibility, wrap certain errors as "no update needed"
      if (error is ApiBusinessException) {
        return RefreshExplanationResult.noUpdate(error.message);
      }
      
      throw error;
    }
  }

  /// Get memories (words for spaced repetition)
  Future<List<WordExplanation>> getMemories(String localTimezone) async {
    logOperation('getMemories', parameters: {'localTimezone': localTimezone});

    try {
      validateStringField(
        localTimezone,
        'localTimezone',
        minLength: 1,
        maxLength: 50,
        patternDescription: 'Must be a valid timezone string',
      );

      final response = await _vocabularyApi.getMemories(localTimezone);
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('getMemories', error);
      throw error;
    }
  }

  /// Get memories for a specific date
  Future<List<WordExplanation>> getMemoriesOnDate(
    String localTimezone,
    String yyyyMMdd,
  ) async {
    logOperation('getMemoriesOnDate', parameters: {
      'localTimezone': localTimezone,
      'date': yyyyMMdd,
    });

    try {
      validateStringField(
        localTimezone,
        'localTimezone',
        minLength: 1,
        maxLength: 50,
      );

      validateStringField(
        yyyyMMdd,
        'yyyyMMdd',
        pattern: RegExp(r'^\d{4}-\d{2}-\d{2}$'),
        patternDescription: 'Date must be in YYYY-MM-DD format',
      );

      final response = await _vocabularyApi.getMemoriesOnDate(localTimezone, yyyyMMdd);
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('getMemoriesOnDate', error);
      throw error;
    }
  }

  /// Get all explanations for a word
  Future<ExplanationsResponse> getExplanationsForWord(
    int wordCollectionId,
    String learningLanguage,
    String explanationLanguage,
  ) async {
    logOperation('getExplanationsForWord', parameters: {
      'wordCollectionId': wordCollectionId,
      'learningLanguage': learningLanguage,
      'explanationLanguage': explanationLanguage,
    });

    try {
      validateNumericField(wordCollectionId, 'wordCollectionId', min: 1);
      validateStringField(learningLanguage, 'learningLanguage', minLength: 2, maxLength: 10);
      validateStringField(explanationLanguage, 'explanationLanguage', minLength: 2, maxLength: 10);

      final response = await _vocabularyApi.getExplanationsForWord(
        wordCollectionId,
        learningLanguage,
        explanationLanguage,
      );

      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('getExplanationsForWord', error);
      throw error;
    }
  }

  /// Switch user's default explanation
  Future<void> switchDefaultExplanation(
    int wordCollectionId,
    int explanationId,
  ) async {
    logOperation('switchDefaultExplanation', parameters: {
      'wordCollectionId': wordCollectionId,
      'explanationId': explanationId,
    });

    try {
      validateNumericField(wordCollectionId, 'wordCollectionId', min: 1);
      validateNumericField(explanationId, 'explanationId', min: 1);

      final response = await _vocabularyApi.switchExplanation(
        wordCollectionId,
        explanationId,
      );

      processVoidResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('switchDefaultExplanation', error);
      throw error;
    }
  }

  /// Enhanced error message creation with context
  @override
  String createErrorMessage(String operation, String? details) {
    final context = {
      'addWord': 'add word to vocabulary',
      'listWords': 'retrieve word list',
      'deleteWord': 'delete word',
      'refreshExplanation': 'refresh word explanation',
      'getMemories': 'retrieve memory words',
      'getMemoriesOnDate': 'retrieve memory words for date',
      'getExplanationsForWord': 'retrieve word explanations',
      'switchDefaultExplanation': 'switch default explanation',
    };

    final operationDescription = context[operation] ?? operation;
    return super.createErrorMessage(operationDescription, details);
  }
}

/// Result class for refresh explanation operations
/// 
/// This maintains compatibility with the existing RefreshExplanationResult
/// while being part of the new service architecture.
class RefreshExplanationResult {
  final WordExplanation? explanation;
  final String? message;
  final bool wasUpdated;

  RefreshExplanationResult._(this.explanation, this.message, this.wasUpdated);

  factory RefreshExplanationResult.updated(WordExplanation explanation) {
    return RefreshExplanationResult._(explanation, null, true);
  }

  factory RefreshExplanationResult.noUpdate(String message) {
    return RefreshExplanationResult._(null, message, false);
  }

  @override
  String toString() {
    if (wasUpdated) {
      return 'RefreshExplanationResult.updated(${explanation?.wordText})';
    } else {
      return 'RefreshExplanationResult.noUpdate($message)';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RefreshExplanationResult &&
        other.explanation == explanation &&
        other.message == message &&
        other.wasUpdated == wasUpdated;
  }

  @override
  int get hashCode => Object.hash(explanation, message, wasUpdated);
}
