import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/entities/add_word_request.dart';
import 'package:new_words/entities/explanations_response.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/providers/vocabulary_provider.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';

import 'vocabulary_provider_test.mocks.dart';

@GenerateMocks([VocabularyServiceV2])
void main() {
  WordExplanation makeWord({
    int id = 1,
    int wordCollectionId = 100,
    int status = ExplanationStatus.ready,
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
      status: status,
    );
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
    });

    group('generateExplanation', () {
      test('re-POSTs with the pending word\'s own languages and fills in place',
          () async {
        final pending = makeWord(status: ExplanationStatus.pending);
        final filled = makeWord(markdown: 'real explanation');

        when(mockService.addWord(any)).thenAnswer((_) async => filled);

        final result = await provider.generateExplanation(pending);

        expect(result, equals(filled));
        expect(result!.isPending, isFalse);
        final captured =
            verify(mockService.addWord(captureAny)).captured.single
                as AddWordRequest;
        expect(captured.wordText, equals(pending.wordText));
        expect(captured.learningLanguage, equals(pending.learningLanguage));
        expect(
          captured.explanationLanguage,
          equals(pending.explanationLanguage),
        );
        expect(provider.isGenerating, isFalse);
      });

      test('keeps pending state when backend returns a still-pending row',
          () async {
        final pending = makeWord(status: ExplanationStatus.pending);
        final stillPending = makeWord(status: ExplanationStatus.pending);

        when(mockService.addWord(any)).thenAnswer((_) async => stillPending);

        final result = await provider.generateExplanation(pending);

        expect(result!.isPending, isTrue);
        expect(provider.isGenerating, isFalse);
      });
    });

    group('loadExplanationsForWord cache bypass', () {
      test('refetches and overwrites when cached entry is still pending',
          () async {
        final word = makeWord();

        final pendingResponse = ExplanationsResponse(
          explanations: [makeWord(status: ExplanationStatus.pending)],
          userDefaultExplanationId: 1,
        );
        final readyResponse = ExplanationsResponse(
          explanations: [makeWord(markdown: 'filled')],
          userDefaultExplanationId: 1,
        );

        when(mockService.getExplanationsForWord(any, any, any))
            .thenAnswer((_) async => pendingResponse);
        // First load caches a pending response.
        await provider.loadExplanationsForWord(word);

        when(mockService.getExplanationsForWord(any, any, any))
            .thenAnswer((_) async => readyResponse);
        // Second load must NOT serve the stale pending cache; it refetches.
        final second = await provider.loadExplanationsForWord(word);

        expect(second.explanations.first.isPending, isFalse);
        verify(mockService.getExplanationsForWord(any, any, any)).called(2);
      });

      test('serves from cache once the cached entry is Ready', () async {
        final word = makeWord();
        final readyResponse = ExplanationsResponse(
          explanations: [makeWord()],
          userDefaultExplanationId: 1,
        );

        when(mockService.getExplanationsForWord(any, any, any))
            .thenAnswer((_) async => readyResponse);

        await provider.loadExplanationsForWord(word);
        await provider.loadExplanationsForWord(word);

        // Second call hits the cache — service invoked only once.
        verify(mockService.getExplanationsForWord(any, any, any)).called(1);
      });
    });
  });
}
