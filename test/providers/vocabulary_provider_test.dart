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
      // Real backoff delays would make the retry tests take tens of seconds;
      // the durations are injected so the timing stays deterministic and short.
      provider = VocabularyProvider(
        mockService,
        initialRetryDelay: const Duration(milliseconds: 1),
        maxRetryDelay: const Duration(milliseconds: 2),
      );
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

    group('add word retry bounds', () {
      test('returns immediately when the first response is ready', () async {
        when(mockService.addWordRaw(any)).thenAnswer(
          (_) async => payloadForWord(makeWord(markdown: 'ready'), status: 0),
        );

        final result = await provider.addNewWord('test');

        expect(result!.markdownExplanation, equals('ready'));
        expect(provider.addError, isNull);
        verify(mockService.addWordRaw(any)).called(1);
      });

      test('stops after maxAddWordRetries pending responses', () async {
        provider = VocabularyProvider(
          mockService,
          maxAddWordRetries: 3,
          initialRetryDelay: const Duration(milliseconds: 1),
          maxRetryDelay: const Duration(milliseconds: 2),
        );
        when(mockService.addWordRaw(any)).thenAnswer(
          (_) async => payloadForWord(makeWord(), status: 1),
        );

        final result = await provider.addNewWord('test');

        expect(result, isNull);
        expect(provider.addError, contains('taking longer than expected'));
        expect(provider.isLoadingAdd, isFalse);
        // maxAddWordRetries pending polls on top of the initial request.
        verify(mockService.addWordRaw(any)).called(4);
      });

      test('backs off exponentially and caps the delay', () async {
        provider = VocabularyProvider(
          mockService,
          maxAddWordRetries: 10,
          initialRetryDelay: const Duration(milliseconds: 10),
          maxRetryDelay: const Duration(milliseconds: 20),
        );

        final callTimes = <Duration>[];
        final stopwatch = Stopwatch()..start();
        var pendingLeft = 8;
        when(mockService.addWordRaw(any)).thenAnswer((_) async {
          callTimes.add(stopwatch.elapsed);
          if (pendingLeft-- > 0) {
            return payloadForWord(makeWord(), status: 1);
          }
          return payloadForWord(makeWord(markdown: 'ready'), status: 0);
        });

        final result = await provider.addNewWord('test');
        stopwatch.stop();

        expect(result!.markdownExplanation, equals('ready'));
        expect(callTimes, hasLength(9));

        final gaps = [
          for (var i = 1; i < callTimes.length; i++)
            callTimes[i] - callTimes[i - 1],
        ];
        // Future.delayed waits at least the requested duration, so the first
        // two gaps prove the doubling (10ms then 20ms).
        expect(gaps[0], greaterThanOrEqualTo(const Duration(milliseconds: 10)));
        expect(gaps[1], greaterThanOrEqualTo(const Duration(milliseconds: 20)));
        // Capped, the eight waits total 10 + 20*7 = 150ms; uncapped doubling
        // would need 2550ms. The bound sits far above the former and far below
        // the latter so scheduling noise cannot flip the verdict.
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 1200)));
      });

      test('cancels the retry loop once the provider is disposed', () async {
        provider = VocabularyProvider(
          mockService,
          maxAddWordRetries: 50,
          initialRetryDelay: const Duration(milliseconds: 5),
          maxRetryDelay: const Duration(milliseconds: 5),
        );

        var calls = 0;
        when(mockService.addWordRaw(any)).thenAnswer((_) async {
          calls++;
          if (calls == 2) provider.dispose();
          return payloadForWord(makeWord(), status: 1);
        });

        final result = await provider.addNewWord('test');

        expect(result, isNull);
        expect(calls, equals(2));

        // No further polling happens after disposal.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(calls, equals(2));
      });
    });
  });
}
