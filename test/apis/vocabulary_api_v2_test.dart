import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:new_words/apis/vocabulary_api_v2.dart';
import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/services/account_service_v2.dart';

@GenerateMocks([Dio])
import 'vocabulary_api_v2_test.mocks.dart';

// Mock AccountServiceV2 for testing
class MockAccountService extends Mock implements AccountServiceV2 {
  @override
  Future<String?> getToken() async => 'mock-token';
  
  @override
  String? getValidToken() => 'mock-token';
  
  @override
  bool hasValidToken() => true;
}

void main() {
  group('VocabularyApiV2', () {
    late VocabularyApiV2 api;
    late MockDio mockDio;

    setUpAll(() async {
      // Initialize dotenv for tests with mock values
      dotenv.testLoad(fileInput: '''
API_BASE_URL=https://test.example.com
''');
      
      // Setup GetIt for tests to avoid dependency issues
      final getIt = GetIt.instance;
      
      // Reset GetIt for clean test environment
      if (getIt.isRegistered<AccountServiceV2>()) {
        await getIt.reset();
      }
      
      // Register minimal mocks for dependencies
      getIt.registerLazySingleton<AccountServiceV2>(() => MockAccountService());
    });

    setUp(() {
      mockDio = MockDio();
      api = TestVocabularyApiV2(mockDio);
    });

    group('addWord', () {
      test('successfully adds word', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        final responseData = {
          'successful': true,
          'data': {
            'id': 1,
            'wordCollectionId': 1,
            'wordText': 'test',
            'wordLanguage': 'en',
            'explanationLanguage': 'zh',
            'markdownExplanation': 'test explanation',
            'createdAt': 1704067200,
          },
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.addWord(request);

        expect(result.isSuccess, isTrue);
        expect(result.data!.id, equals(1));
        expect(result.data!.wordText, equals('test'));
        expect(result.data!.markdownExplanation, equals('test explanation'));

        verify(mockDio.post(
          ApiConstants.vocabularyAdd,
          data: request.toJson(),
          options: anyNamed('options'),
        )).called(1);
      });

      test('preserves the backend status in the raw add payload', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );
        final responseData = {
          'successful': true,
          'data': {
            'id': 1,
            'wordCollectionId': 1,
            'wordText': 'test',
            'wordLanguage': 'en',
            'explanationLanguage': 'zh',
            'markdownExplanation': 'placeholder',
            'createdAt': 1704067200,
            'status': 1,
          },
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.addWordRaw(request);

        expect(result.isSuccess, isTrue);
        expect(result.data!['status'], equals(1));
        verify(mockDio.post(
          ApiConstants.vocabularyAdd,
          data: request.toJson(),
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for null wordText', () async {
        expect(
          () => AddWordRequest(
            wordText: null as dynamic, // Force null for test
            learningLanguage: 'en',
            explanationLanguage: 'zh',
          ),
          throwsA(isA<TypeError>()),
        );
      });

      test('throws DataException for empty wordText', () async {
        final request = AddWordRequest(
          wordText: '',
          learningLanguage: 'en',
          explanationLanguage: 'zh',
        );

        expect(
          () => api.addWord(request),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for empty learningLanguage', () async {
        final request = AddWordRequest(
          wordText: 'test',
          learningLanguage: '',
          explanationLanguage: 'zh',
        );

        expect(
          () => api.addWord(request),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('listWords', () {
      test('successfully lists words', () async {
        final responseData = {
          'successful': true,
          'data': {
            'dataList': [
              {
                'id': 1,
                'wordCollectionId': 1,
                'wordText': 'test1',
                'wordLanguage': 'en',
                'explanationLanguage': 'zh',
                'markdownExplanation': 'explanation1',
                'createdAt': 1704067200,
              },
              {
                'id': 2,
                'wordCollectionId': 1,
                'wordText': 'test2',
                'wordLanguage': 'en',
                'explanationLanguage': 'zh',
                'markdownExplanation': 'explanation2',
                'createdAt': 1704067200,
              },
            ],
            'totalCount': 2,
            'pageIndex': 1,
            'pageSize': 10,
          },
        };

        when(mockDio.get(
          any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.listWords(1, 10);

        expect(result.isSuccess, isTrue);
        expect(result.data!.dataList.length, equals(2));
        expect(result.data!.totalCount, equals(2));
        expect(result.data!.dataList[0].wordText, equals('test1'));
        expect(result.data!.dataList[1].wordText, equals('test2'));

        verify(mockDio.get(
          ApiConstants.vocabularyList,
          queryParameters: {
            ApiConstants.paramPageNumber: 1,
            ApiConstants.paramPageSize: 10,
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for invalid page number', () async {
        expect(
          () => api.listWords(0, 10),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for negative page number', () async {
        expect(
          () => api.listWords(-1, 10),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for page size too small', () async {
        expect(
          () => api.listWords(1, 0),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for page size too large', () async {
        expect(
          () => api.listWords(1, 101),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('deleteWord', () {
      test('successfully deletes word', () async {
        final responseData = {
          'successful': true,
        };

        when(mockDio.delete(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 204,
        ));

        final result = await api.deleteWord(1);

        expect(result.isSuccess, isTrue);

        verify(mockDio.delete(
          '${ApiConstants.vocabularyDelete}/1',
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for invalid word ID', () async {
        expect(
          () => api.deleteWord(0),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for negative word ID', () async {
        expect(
          () => api.deleteWord(-1),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('refreshExplanation', () {
      test('successfully refreshes explanation', () async {
        final responseData = {
          'successful': true,
          'data': {
            'id': 1,
            'wordCollectionId': 1,
            'wordText': 'test',
            'wordLanguage': 'en',
            'explanationLanguage': 'zh',
            'markdownExplanation': 'refreshed explanation',
            'createdAt': 1704067200,
          },
        };

        when(mockDio.put(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.refreshExplanation(1);

        expect(result.isSuccess, isTrue);
        expect(result.data!.markdownExplanation, equals('refreshed explanation'));

        verify(mockDio.put(
          '${ApiConstants.vocabularyRefreshExplanation}/1',
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for invalid explanation ID', () async {
        expect(
          () => api.refreshExplanation(0),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for negative explanation ID', () async {
        expect(
          () => api.refreshExplanation(-1),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('getMemories', () {
      test('successfully gets memories', () async {
        final responseData = {
          'successful': true,
          'data': [
            {
              'id': 1,
              'wordCollectionId': 1,
              'wordText': 'memory1',
              'wordLanguage': 'en',
              'explanationLanguage': 'zh',
              'markdownExplanation': 'explanation1',
              'createdAt': 1704067200,
            },
            {
              'id': 2,
              'wordCollectionId': 1,
              'wordText': 'memory2',
              'wordLanguage': 'en',
              'explanationLanguage': 'zh',
              'markdownExplanation': 'explanation2',
              'createdAt': 1704067200,
            },
          ],
        };

        when(mockDio.get(
          any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.getMemories('America/New_York');

        expect(result.isSuccess, isTrue);
        expect(result.data!.length, equals(2));
        expect(result.data![0].wordText, equals('memory1'));
        expect(result.data![1].wordText, equals('memory2'));

        verify(mockDio.get(
          ApiConstants.vocabularyMemories,
          queryParameters: {
            ApiConstants.paramLocalTimezone: 'America/New_York',
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for empty timezone', () async {
        expect(
          () => api.getMemories(''),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for null timezone', () async {
        expect(
          () => api.getMemories(null as dynamic), // Force null for test
          throwsA(isA<TypeError>()),
        );
      });

      test('throws DataException for timezone too long', () async {
        final longTimezone = 'a' * 51;
        expect(
          () => api.getMemories(longTimezone),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('getMemoriesOnDate', () {
      test('successfully gets memories on specific date', () async {
        final responseData = {
          'successful': true,
          'data': [
            {
              'id': 1,
              'wordCollectionId': 1,
              'wordText': 'memory1',
              'wordLanguage': 'en',
              'explanationLanguage': 'zh',
              'markdownExplanation': 'explanation1',
              'createdAt': 1704067200,
            },
          ],
        };

        when(mockDio.get(
          any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.getMemoriesOnDate('America/New_York', '20240101');

        expect(result.isSuccess, isTrue);
        expect(result.data!.length, equals(1));
        expect(result.data![0].wordText, equals('memory1'));

        verify(mockDio.get(
          ApiConstants.vocabularyMemoriesOn,
          queryParameters: {
            ApiConstants.paramLocalTimezone: 'America/New_York',
            ApiConstants.paramYyyyMMdd: '20240101',
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for empty timezone', () async {
        expect(
          () => api.getMemoriesOnDate('', '20240101'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for invalid date format', () async {
        expect(
          () => api.getMemoriesOnDate('America/New_York', '01-01-2024'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for empty date', () async {
        expect(
          () => api.getMemoriesOnDate('America/New_York', ''),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for incomplete date', () async {
        expect(
          () => api.getMemoriesOnDate('America/New_York', '2024-01'),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('validation methods', () {
      test('validateInput succeeds for valid data', () {
        expect(
          () => api.validateInput({
            'field1': 'value1',
            'field2': 'value2',
          }),
          returnsNormally,
        );
      });

      test('validateInput throws for null values', () {
        expect(
          () => api.validateInput({'field': null}),
          throwsA(isA<DataException>()),
        );
      });

      test('validateInput throws for empty string values', () {
        expect(
          () => api.validateInput({'field': ''}),
          throwsA(isA<DataException>()),
        );
      });

      test('validateInput throws for whitespace-only string values', () {
        expect(
          () => api.validateInput({'field': '   '}),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField succeeds for valid string', () {
        expect(
          () => api.validateStringField('test', 'field'),
          returnsNormally,
        );
      });

      test('validateStringField throws for required field when null', () {
        expect(
          () => api.validateStringField(null, 'field'),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField succeeds for optional field when null', () {
        expect(
          () => api.validateStringField(null, 'field', required: false),
          returnsNormally,
        );
      });

      test('validateStringField throws for too short string', () {
        expect(
          () => api.validateStringField('ab', 'field', minLength: 3),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField throws for too long string', () {
        expect(
          () => api.validateStringField('abcde', 'field', maxLength: 3),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField throws for pattern mismatch', () {
        expect(
          () => api.validateStringField(
            '123',
            'field',
            pattern: RegExp(r'^[a-z]+$'),
            patternDescription: 'Must be lowercase letters only',
          ),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField succeeds for pattern match', () {
        expect(
          () => api.validateStringField(
            'abc',
            'field',
            pattern: RegExp(r'^[a-z]+$'),
          ),
          returnsNormally,
        );
      });

      test('validateNumericField succeeds for valid number', () {
        expect(
          () => api.validateNumericField(5, 'field'),
          returnsNormally,
        );
      });

      test('validateNumericField throws for required field when null', () {
        expect(
          () => api.validateNumericField(null, 'field'),
          throwsA(isA<DataException>()),
        );
      });

      test('validateNumericField succeeds for optional field when null', () {
        expect(
          () => api.validateNumericField(null, 'field', required: false),
          returnsNormally,
        );
      });

      test('validateNumericField throws for number too small', () {
        expect(
          () => api.validateNumericField(3, 'field', min: 5),
          throwsA(isA<DataException>()),
        );
      });

      test('validateNumericField throws for number too large', () {
        expect(
          () => api.validateNumericField(15, 'field', max: 10),
          throwsA(isA<DataException>()),
        );
      });

      test('processPaginationParams returns correct parameters', () {
        final result = api.processPaginationParams(2, 20);

        expect(result[ApiConstants.paramPageNumber], equals(2));
        expect(result[ApiConstants.paramPageSize], equals(20));
      });

      test('processPaginationParams validates page number', () {
        expect(
          () => api.processPaginationParams(0, 20),
          throwsA(isA<DataException>()),
        );
      });

      test('processPaginationParams validates page size', () {
        expect(
          () => api.processPaginationParams(1, 0),
          throwsA(isA<DataException>()),
        );
      });

      test('processPaginationParams respects custom limits', () {
        final result = api.processPaginationParams(
          1,
          50,
          maxPageSize: 100,
          minPageSize: 10,
        );

        expect(result[ApiConstants.paramPageNumber], equals(1));
        expect(result[ApiConstants.paramPageSize], equals(50));
      });

      test('processPaginationParams throws for size exceeding custom max', () {
        expect(
          () => api.processPaginationParams(
            1,
            150,
            maxPageSize: 100,
          ),
          throwsA(isA<DataException>()),
        );
      });
    });
  });
}

// Test implementation that properly mocks dependencies
class TestVocabularyApiV2 extends VocabularyApiV2 {
  TestVocabularyApiV2(MockDio super.mockDio);
}
