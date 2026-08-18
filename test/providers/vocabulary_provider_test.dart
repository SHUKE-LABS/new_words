import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/explanations_response.dart';
import 'package:new_words/entities/page_data.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/providers/vocabulary_provider.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';
import 'package:new_words/user_session.dart';

import 'vocabulary_provider_test.mocks.dart';

@GenerateMocks([VocabularyServiceV2])
void main() {
  WordExplanation makeWord({
    int id = 1,
    int wordCollectionId = 100,
    String markdown = 'explanation',
  }) {
    return WordExplanation(
      id: id,
      wordCollectionId: wordCollectionId,
      wordText: 'test',
      learningLanguage: 'en',
      explanationLanguage: 'zh',
      markdownExplanation: markdown,
      createdAt: 1234567890,
      updatedAt: 1234567890,
    );
  }

  Map<String, dynamic> payloadForWord(
    WordExplanation word, {
    required int status,
  }) {
    return word.toJson()..['status'] = status;
  }

  group('VocabularyProvider', () {
    late VocabularyProvider provider;
    late MockVocabularyServiceV2 mockService;

    setUpAll(() {
      // VocabularyProvider reads AppConfig.pageSize at construction, which
      // falls back to dotenv; load a minimal env so it doesn't throw.
      dotenv.testLoad(mergeWith: {'PAGE_SIZE': '20'});
    });

    setUp(() {
      mockService = MockVocabularyServiceV2();
      provider = VocabularyProvider(mockService);
      UserSession().currentLearningLanguage = 'en';
      UserSession().nativeLanguage = 'zh';

      when(mockService.listWords(any, any)).thenAnswer(
        (_) async => PageData<WordExplanation>(
          dataList: [],
          totalCount: 0,
          pageIndex: 1,
          pageSize: 20,
        ),
      );
    });

    tearDown(() {
      UserSession().currentLearningLanguage = null;
      UserSession().nativeLanguage = null;
    });

    test(
      'retries any number of Pending add responses and merges the Ready result once',
      () async {
        final existing = makeWord(id: 1, markdown: 'old explanation');
        final pendingPayloads = List.generate(
          5,
          (_) => payloadForWord(
            makeWord(id: 1, markdown: 'placeholder'),
            status: 1,
          ),
        );
        final readyPayload = payloadForWord(
          makeWord(id: 1, markdown: 'real explanation'),
          status: 0,
        );

        when(mockService.listWords(any, any)).thenAnswer(
          (_) async => PageData<WordExplanation>(
            dataList: [existing],
            totalCount: 1,
            pageIndex: 1,
            pageSize: 20,
          ),
        );
        await provider.fetchWords();

        final responses = [...pendingPayloads, readyPayload];
        when(
          mockService.addWordRaw(any),
        ).thenAnswer((_) async => responses.removeAt(0));

        final result = await provider.addNewWord('test');

        expect(result!.markdownExplanation, equals('real explanation'));
        expect(result.toJson().containsKey('status'), isFalse);
        expect(provider.words, hasLength(1));
        expect(
          provider.words.single.markdownExplanation,
          equals('real explanation'),
        );

        final verification = verify(mockService.addWordRaw(captureAny));
        verification.called(pendingPayloads.length + 1);
        final captured = verification.captured.cast<AddWordRequest>();
        expect(captured, hasLength(pendingPayloads.length + 1));
        for (final request in captured.skip(1)) {
          expect(request.toJson(), equals(captured.first.toJson()));
        }
        expect(captured.first.toJson(), {
          'wordText': 'test',
          'learningLanguage': 'en',
          'explanationLanguage': 'zh',
        });
      },
    );

    test('serves cached explanations without a second request', () async {
      final word = makeWord();
      final response = ExplanationsResponse(
        explanations: [word],
        userDefaultExplanationId: word.id,
      );
      when(
        mockService.getExplanationsForWord(any, any, any),
      ).thenAnswer((_) async => response);

      final first = await provider.loadExplanationsForWord(word);
      final second = await provider.loadExplanationsForWord(word);

      expect(first, same(response));
      expect(second, same(response));
      verify(mockService.getExplanationsForWord(any, any, any)).called(1);
    });
  });
}
