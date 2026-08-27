import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/stories_api_v2.dart';
import 'package:new_words/apis/vocabulary_api_v2.dart';
import 'package:new_words/entities/page_data.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/features/stories/presentation/story_detail_screen.dart';
import 'package:new_words/features/word_detail/presentation/word_detail_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/stories_provider.dart';
import 'package:new_words/providers/vocabulary_provider.dart';
import 'package:new_words/services/stories_service_v2.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';
import 'package:provider/provider.dart';

import '../../mocks/mock_app_logger.dart';

/// A stories service that answers from memory, so the whole practice entry —
/// look up, generate, fail — runs without a server.
class _FakeStoriesService extends StoriesServiceV2 {
  _FakeStoriesService({this.remote = const [], this.generated = const []})
    : super(storiesApi: StoriesApiV2(Dio()), logger: MockAppLogger());

  final List<Story> remote;

  /// What a generation returns; empty stands for "the server generated
  /// nothing".
  final List<Story> generated;

  /// Thrown from `generateStories` when set, so the provider records an error.
  Object? generateFailure;

  int fetchCount = 0;
  final List<List<String>?> generateCalls = [];

  /// Holds the lookup open, so the in-flight state is observable.
  Completer<void>? holdFetch;

  @override
  Future<PageData<Story>> getMyStories(int pageNumber, int pageSize) async {
    fetchCount++;
    final gate = holdFetch;
    if (gate != null) await gate.future;
    return PageData(
      dataList: remote,
      totalCount: remote.length,
      pageIndex: pageNumber,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Story>> generateStories({List<String>? customWords}) async {
    generateCalls.add(customWords);
    final failure = generateFailure;
    if (failure != null) throw failure;
    return generated;
  }
}

/// The story screen resolves the shared TTS singleton; nothing here plays.
class _FakeTtsService extends TtsService {
  @override
  bool get isSupported => false;

  @override
  Future<void> init({String? language}) async {}

  @override
  Future<List<String>> getLanguages() async => const [];

  @override
  Future<void> stop() async {}
}

void main() {
  setUpAll(() {
    // AppConfig.pageSize and AppConfig.isProduction both read dotenv.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  Story storyWith(int id, String words) => Story(
    id: id,
    userId: 1,
    content: 'She waited for a long time. Then it rained on the roof.',
    storyWords: words,
    learningLanguage: 'en',
    firstReadAt: 1700000000,
    favoriteCount: 0,
    createdAt: 1700000000,
  );

  // wordCollectionId 0 keeps the background explanation load out of the way:
  // the screen skips it, so nothing but the practice entry touches a service.
  final explanation = WordExplanation(
    id: 1,
    wordCollectionId: 0,
    wordText: 'calm',
    learningLanguage: 'en',
    explanationLanguage: 'zh',
    markdownExplanation: 'calm — 平静的',
    createdAt: 1700000000,
    updatedAt: 1700000000,
  );

  late _FakeStoriesService service;
  late StoriesProvider stories;

  setUp(() {
    if (GetIt.I.isRegistered<TtsService>()) {
      GetIt.I.unregister<TtsService>();
    }
    GetIt.I.registerSingleton<TtsService>(_FakeTtsService());
  });

  tearDown(() => GetIt.I.unregister<TtsService>());

  Future<void> pumpWordDetail(WidgetTester tester) async {
    stories = StoriesProvider(service);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoriesProvider>.value(value: stories),
          ChangeNotifierProvider<VocabularyProvider>(
            create:
                (_) => VocabularyProvider(
                  VocabularyServiceV2(VocabularyApiV2(Dio())),
                ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WordDetailScreen(wordExplanation: explanation),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapPractice(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.school));
    await tester.pumpAndSettle();
  }

  group('word list → word detail → Practice', () {
    testWidgets('an existing story opens straight into practice', (
      tester,
    ) async {
      service = _FakeStoriesService(remote: [storyWith(9, 'calm')]);
      await pumpWordDetail(tester);
      await stories.fetchMyStories();
      await tester.pumpAndSettle();
      final fetchesBefore = service.fetchCount;

      await tapPractice(tester);

      final screen = tester.widget<StoryDetailScreen>(
        find.byType(StoryDetailScreen),
      );
      expect(screen.story.id, 9);
      expect(service.fetchCount, fetchesBefore, reason: 'already in memory');
      expect(service.generateCalls, isEmpty);
    });

    testWidgets('a story the tab never loaded is fetched, then opened', (
      tester,
    ) async {
      service = _FakeStoriesService(remote: [storyWith(4, 'calm')]);
      await pumpWordDetail(tester);
      expect(stories.myStories, isEmpty);

      await tapPractice(tester);

      expect(service.fetchCount, 1);
      final screen = tester.widget<StoryDetailScreen>(
        find.byType(StoryDetailScreen),
      );
      expect(screen.story.id, 4);
    });

    testWidgets('no story: confirming generates one for this word and opens '
        'it', (tester) async {
      service = _FakeStoriesService(
        remote: [storyWith(1, 'river')],
        generated: [storyWith(12, 'calm')],
      );
      await pumpWordDetail(tester);

      await tapPractice(tester);
      expect(find.text('No story yet'), findsOneWidget);
      expect(
        find.text('None of your stories uses “calm” yet. Generate one now?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(service.generateCalls, [
        ['calm'],
      ]);
      final screen = tester.widget<StoryDetailScreen>(
        find.byType(StoryDetailScreen),
      );
      expect(screen.story.id, 12);
    });

    testWidgets('declining generates nothing and goes nowhere', (tester) async {
      service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
      await pumpWordDetail(tester);

      await tapPractice(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(service.generateCalls, isEmpty);
      expect(find.byType(StoryDetailScreen), findsNothing);
      expect(find.byType(WordDetailScreen), findsOneWidget);
    });

    testWidgets('a generation that produces nothing says so', (tester) async {
      service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
      await pumpWordDetail(tester);

      await tapPractice(tester);
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not generate a story for this word'),
        findsOneWidget,
      );
      expect(find.byType(StoryDetailScreen), findsNothing);
    });

    testWidgets('a failed generation reports the provider\'s own error', (
      tester,
    ) async {
      service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
      service.generateFailure = Exception('story service is down');
      await pumpWordDetail(tester);

      await tapPractice(tester);
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(stories.generateError, isNotNull);
      expect(find.textContaining('story service is down'), findsOneWidget);
      expect(find.byType(StoryDetailScreen), findsNothing);
    });

    testWidgets('the affordance is inert while a lookup is in flight', (
      tester,
    ) async {
      service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
      final gate = Completer<void>();
      service.holdFetch = gate;
      await pumpWordDetail(tester);

      await tester.tap(find.byIcon(Icons.school));
      await tester.pump();

      // The spinner has replaced the icon, so there is nothing left to tap
      // into a second lookup.
      expect(find.byIcon(Icons.school), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      service.holdFetch = null;
      await tester.pumpAndSettle();
      expect(service.fetchCount, 1);
      expect(find.byIcon(Icons.school), findsOneWidget);
    });
  });
}
