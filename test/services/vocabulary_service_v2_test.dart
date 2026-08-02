import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';
import 'package:new_words/apis/vocabulary_api_v2.dart';
import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/entities/page_data.dart';

@GenerateMocks([VocabularyApiV2])
import 'vocabulary_service_v2_test.mocks.dart';

void main() {
  group('VocabularyServiceV2', () {
    late VocabularyServiceV2 service;
    late MockVocabularyApiV2 mockApi;

    setUp(() {
      mockApi = MockVocabularyApiV2();
      service = VocabularyServiceV2(mockApi);
    });

    group('addWord', () {
      test('successfully adds word', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        final expectedWord = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'test explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final apiResponse = ApiResponseV2<WordExplanation>.success(expectedWord);

        when(mockApi.addWord(request)).thenAnswer((_) async => apiResponse);

        final result = await service.addWord(request);

        expect(result.id, equals(1));
        expect(result.wordText, equals('test'));
        expect(result.markdownExplanation, equals('test explanation'));

        verify(mockApi.addWord(request)).called(1);
      });

      test('preserves the backend status in the raw add payload', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );
        final payload = <String, dynamic>{
          'id': 1,
          'wordCollectionId': 1,
          'wordText': 'test',
          'learningLanguage': 'en',
          'explanationLanguage': 'zh',
          'markdownExplanation': 'placeholder',
          'createdAt': 1704067200,
          'status': 1,
        };

        when(mockApi.addWordRaw(request)).thenAnswer(
          (_) async => ApiResponseV2<Map<String, dynamic>>.success(payload),
        );

        final result = await service.addWordRaw(request);

        expect(result['status'], equals(1));
        verify(mockApi.addWordRaw(request)).called(1);
      });

      test('throws DataException for empty wordText', () async {
        final request = AddWordRequest(
          wordText: '',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for empty learningLanguage', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: '',
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for empty explanationLanguage', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: '',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for wordText too short', () async {
        final request = AddWordRequest(
          wordText: '', // Empty string is less than minWordLength
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for wordText too long', () async {
        final request = AddWordRequest(
          wordText: 'a' * 101, // More than maxWordLength (assuming 100)
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for invalid wordText pattern', () async {
        final request = AddWordRequest(
          wordText: 'test123!@#', // Contains invalid characters
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for learningLanguage too short', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'e', // Less than 2 chars
          explanationLanguage: 'zh',
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('throws DataException for explanationLanguage too long', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'a' * 11, // More than 10 chars
        );

        expect(
          () => service.addWord(request),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.addWord(any));
      });

      test('handles API error gracefully', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        final apiResponse = ApiResponseV2<WordExplanation>.error(
          'Validation error',
          statusCode: 400,
          errorCode: 1001,
        );

        when(mockApi.addWord(request)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.addWord(request),
          throwsA(isA<ApiBusinessException>()),
        );

        verify(mockApi.addWord(request)).called(1);
      });
    });

    group('listWords', () {
      test('successfully lists words', () async {
        final expectedWords = <WordExplanation>[
          WordExplanation(
            id: 1,
            wordCollectionId: 1,
            wordText: 'test1',
            learningLanguage: 'en',
            explanationLanguage: 'zh',
            markdownExplanation: 'explanation1',
            createdAt: 1704067200,
            updatedAt: 1704067200,
          ),
          WordExplanation(
            id: 2,
            wordCollectionId: 1,
            wordText: 'test2',
            learningLanguage: 'en',
            explanationLanguage: 'zh',
            markdownExplanation: 'explanation2',
            createdAt: 1704067200,
            updatedAt: 1704067200,
          ),
        ];

        final expectedPageData = PageData<WordExplanation>(
          dataList: expectedWords,
          totalCount: 2,
          pageIndex: 1,
          pageSize: 10,
        );

        final apiResponse = ApiResponseV2<PageData<WordExplanation>>.success(expectedPageData);

        when(mockApi.listWords(1, 10)).thenAnswer((_) async => apiResponse);

        final result = await service.listWords(1, 10);

        expect(result.dataList.length, equals(2));
        expect(result.totalCount, equals(2));
        expect(result.dataList[0].wordText, equals('test1'));
        expect(result.dataList[1].wordText, equals('test2'));

        verify(mockApi.listWords(1, 10)).called(1);
      });

      test('throws DataException for invalid page number', () async {
        expect(
          () => service.listWords(0, 10),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.listWords(any, any));
      });

      test('throws DataException for negative page number', () async {
        expect(
          () => service.listWords(-1, 10),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.listWords(any, any));
      });

      test('throws DataException for page size too small', () async {
        expect(
          () => service.listWords(1, 0),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.listWords(any, any));
      });

      test('throws DataException for page size too large', () async {
        expect(
          () => service.listWords(1, 101), // Assuming max is 100
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.listWords(any, any));
      });

      test('handles API error gracefully', () async {
        final apiResponse = ApiResponseV2<PageData<WordExplanation>>.error(
          'Invalid request',
          statusCode: 400,
          errorCode: 1002,
        );

        when(mockApi.listWords(1, 10)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.listWords(1, 10),
          throwsA(isA<ApiBusinessException>()),
        );

        verify(mockApi.listWords(1, 10)).called(1);
      });
    });

    group('deleteWord', () {
      test('successfully deletes word', () async {
        final apiResponse = ApiResponseV2<void>.success(null);

        when(mockApi.deleteWord(1)).thenAnswer((_) async => apiResponse);

        await service.deleteWord(1);

        verify(mockApi.deleteWord(1)).called(1);
      });

      test('throws DataException for invalid word ID', () async {
        expect(
          () => service.deleteWord(0),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.deleteWord(any));
      });

      test('throws DataException for negative word ID', () async {
        expect(
          () => service.deleteWord(-1),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.deleteWord(any));
      });

      test('handles API error gracefully', () async {
        final apiResponse = ApiResponseV2<void>.error(
          'Word not found',
          statusCode: 404,
          errorCode: 404,
        );

        when(mockApi.deleteWord(1)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.deleteWord(1),
          throwsA(isA<ApiBusinessException>()),
        );

        verify(mockApi.deleteWord(1)).called(1);
      });
    });

    group('refreshExplanation', () {
      test('successfully refreshes explanation', () async {
        final originalExplanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'old explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final refreshedExplanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'refreshed explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final apiResponse = ApiResponseV2<WordExplanation>.success(refreshedExplanation);

        when(mockApi.refreshExplanation(1)).thenAnswer((_) async => apiResponse);

        final result = await service.refreshExplanation(originalExplanation);

        expect(result.wasUpdated, isTrue);
        expect(result.explanation!.markdownExplanation, equals('refreshed explanation'));

        verify(mockApi.refreshExplanation(1)).called(1);
      });

      test('returns no update when API indicates no refresh needed', () async {
        final originalExplanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final apiResponse = ApiResponseV2<WordExplanation>.error(
          'No update needed',
          statusCode: 200,
          errorCode: 1001, // Positive error code indicates no update needed
        );

        when(mockApi.refreshExplanation(1)).thenAnswer((_) async => apiResponse);

        final result = await service.refreshExplanation(originalExplanation);

        expect(result.wasUpdated, isFalse);
        expect(result.message, equals('No update needed'));

        verify(mockApi.refreshExplanation(1)).called(1);
      });

      test('throws DataException for invalid explanation ID', () async {
        final invalidExplanation = WordExplanation(
          id: 0, // Invalid ID
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        expect(
          () => service.refreshExplanation(invalidExplanation),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.refreshExplanation(any));
      });

      test('handles API business exception gracefully', () async {
        final originalExplanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        when(mockApi.refreshExplanation(1)).thenThrow(
          ApiBusinessException('Service unavailable', backendErrorCode: 503),
        );

        final result = await service.refreshExplanation(originalExplanation);

        expect(result.wasUpdated, isFalse);
        expect(result.message, equals('Service unavailable'));

        verify(mockApi.refreshExplanation(1)).called(1);
      });

      test('throws other exceptions normally', () async {
        final originalExplanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        when(mockApi.refreshExplanation(1)).thenThrow(
          NetworkException('Connection failed'),
        );

        expect(
          () => service.refreshExplanation(originalExplanation),
          throwsA(isA<NetworkException>()),
        );

        verify(mockApi.refreshExplanation(1)).called(1);
      });
    });

    group('getMemories', () {
      test('successfully gets memories', () async {
        final expectedMemories = <WordExplanation>[
          WordExplanation(
            id: 1,
            wordCollectionId: 1,
            wordText: 'memory1',
            learningLanguage: 'en',
            explanationLanguage: 'zh',
            markdownExplanation: 'explanation1',
            createdAt: 1704067200,
            updatedAt: 1704067200,
          ),
          WordExplanation(
            id: 2,
            wordCollectionId: 1,
            wordText: 'memory2',
            learningLanguage: 'en',
            explanationLanguage: 'zh',
            markdownExplanation: 'explanation2',
            createdAt: 1704067200,
            updatedAt: 1704067200,
          ),
        ];

        final apiResponse = ApiResponseV2<List<WordExplanation>>.success(expectedMemories);

        when(mockApi.getMemories('America/New_York')).thenAnswer((_) async => apiResponse);

        final result = await service.getMemories('America/New_York');

        expect(result.length, equals(2));
        expect(result[0].wordText, equals('memory1'));
        expect(result[1].wordText, equals('memory2'));

        verify(mockApi.getMemories('America/New_York')).called(1);
      });

      test('throws DataException for empty timezone', () async {
        expect(
          () => service.getMemories(''),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemories(any));
      });

      test('throws DataException for timezone too long', () async {
        final longTimezone = 'a' * 51;
        expect(
          () => service.getMemories(longTimezone),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemories(any));
      });

      test('handles API error gracefully', () async {
        final apiResponse = ApiResponseV2<List<WordExplanation>>.error(
          'Invalid timezone',
          statusCode: 400,
          errorCode: 1003,
        );

        when(mockApi.getMemories('America/New_York')).thenAnswer((_) async => apiResponse);

        expect(
          () => service.getMemories('America/New_York'),
          throwsA(isA<ApiBusinessException>()),
        );

        verify(mockApi.getMemories('America/New_York')).called(1);
      });
    });

    group('getMemoriesOnDate', () {
      test('successfully gets memories on specific date', () async {
        final expectedMemories = <WordExplanation>[
          WordExplanation(
            id: 1,
            wordCollectionId: 1,
            wordText: 'memory1',
            learningLanguage: 'en',
            explanationLanguage: 'zh',
            markdownExplanation: 'explanation1',
            createdAt: 1704067200,
            updatedAt: 1704067200,
          ),
        ];

        final apiResponse = ApiResponseV2<List<WordExplanation>>.success(expectedMemories);

        when(mockApi.getMemoriesOnDate('America/New_York', '2024-01-01'))
            .thenAnswer((_) async => apiResponse);

        final result = await service.getMemoriesOnDate('America/New_York', '2024-01-01');

        expect(result.length, equals(1));
        expect(result[0].wordText, equals('memory1'));

        verify(mockApi.getMemoriesOnDate('America/New_York', '2024-01-01')).called(1);
      });

      test('throws DataException for empty timezone', () async {
        expect(
          () => service.getMemoriesOnDate('', '2024-01-01'),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemoriesOnDate(any, any));
      });

      test('throws DataException for invalid date format', () async {
        expect(
          () => service.getMemoriesOnDate('America/New_York', '01-01-2024'),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemoriesOnDate(any, any));
      });

      test('throws DataException for empty date', () async {
        expect(
          () => service.getMemoriesOnDate('America/New_York', ''),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemoriesOnDate(any, any));
      });

      test('throws DataException for incomplete date', () async {
        expect(
          () => service.getMemoriesOnDate('America/New_York', '2024-01'),
          throwsA(isA<DataException>()),
        );

        verifyNever(mockApi.getMemoriesOnDate(any, any));
      });

      test('handles API error gracefully', () async {
        final apiResponse = ApiResponseV2<List<WordExplanation>>.error(
          'Date not found',
          statusCode: 404,
          errorCode: 1004,
        );

        when(mockApi.getMemoriesOnDate('America/New_York', '2024-01-01'))
            .thenAnswer((_) async => apiResponse);

        expect(
          () => service.getMemoriesOnDate('America/New_York', '2024-01-01'),
          throwsA(isA<ApiBusinessException>()),
        );

        verify(mockApi.getMemoriesOnDate('America/New_York', '2024-01-01')).called(1);
      });
    });

    group('RefreshExplanationResult', () {
      test('equals works correctly for updated results', () {
        final explanation1 = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final explanation2 = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final result1 = RefreshExplanationResult.updated(explanation1);
        final result2 = RefreshExplanationResult.updated(explanation2);

        expect(result1, equals(result2));
        expect(result1.hashCode, equals(result2.hashCode));
      });

      test('equals works correctly for no update results', () {
        final result1 = RefreshExplanationResult.noUpdate('message');
        final result2 = RefreshExplanationResult.noUpdate('message');

        expect(result1, equals(result2));
        expect(result1.hashCode, equals(result2.hashCode));
      });

      test('toString works correctly', () {
        final explanation = WordExplanation(
          id: 1,
          wordCollectionId: 1,
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
          markdownExplanation: 'explanation',
          createdAt: 1704067200,
          updatedAt: 1704067200,
        );

        final updatedResult = RefreshExplanationResult.updated(explanation);
        final noUpdateResult = RefreshExplanationResult.noUpdate('No update needed');

        expect(updatedResult.toString(), contains('RefreshExplanationResult.updated(test)'));
        expect(noUpdateResult.toString(), contains('RefreshExplanationResult.noUpdate(No update needed)'));
      });
    });

    group('error message creation', () {
      test('creates enhanced error messages', () {
        final testService = VocabularyServiceV2(mockApi);
        
        final message = testService.createErrorMessage('addWord', 'Validation failed');
        expect(message, contains('add word to vocabulary'));
        expect(message, contains('Validation failed'));
      });

      test('handles unknown operations', () {
        final testService = VocabularyServiceV2(mockApi);
        
        final message = testService.createErrorMessage('unknownOperation', 'Some error');
        expect(message, contains('unknownOperation'));
        expect(message, contains('Some error'));
      });
    });
  });
}
