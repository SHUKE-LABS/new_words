import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/apis/stories_api_v2.dart';
import 'package:new_words/entities/page_data.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/utils/practice_entry.dart';
import 'package:new_words/providers/stories_provider.dart';
import 'package:new_words/services/stories_service_v2.dart';

import '../../mocks/mock_app_logger.dart';

/// A stories service that answers from memory and counts every fetch: what the
/// entry point must not do is fetch twice, or fetch at all when the list is
/// already loaded.
class _FakeStoriesService extends StoriesServiceV2 {
  _FakeStoriesService({this.remote = const []})
    : super(storiesApi: StoriesApiV2(Dio()), logger: MockAppLogger());

  /// What the server would return for the first page of My Stories.
  final List<Story> remote;

  int fetchCount = 0;

  @override
  Future<PageData<Story>> getMyStories(int pageNumber, int pageSize) async {
    fetchCount++;
    return PageData(
      dataList: remote,
      totalCount: remote.length,
      pageIndex: pageNumber,
      pageSize: pageSize,
    );
  }
}

void main() {
  setUpAll(() {
    // StoriesProvider reads AppConfig.pageSize, which reads dotenv.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  Story storyWith(int id, String words) => Story(
    id: id,
    userId: 1,
    content: 'A story about $words.',
    storyWords: words,
    learningLanguage: 'en',
    firstReadAt: 1700000000,
    favoriteCount: 0,
    createdAt: 1700000000,
  );

  group('PracticeEntry.resolveStory', () {
    test('finds a story already in memory, without fetching', () async {
      final loaded = _FakeStoriesService(
        remote: [storyWith(1, 'calm'), storyWith(2, 'river')],
      );
      final withStories = StoriesProvider(loaded);
      await withStories.fetchMyStories();

      final story = await PracticeEntry.resolveStory(withStories, 'river');

      expect(story?.id, 2);
      expect(loaded.fetchCount, 1, reason: 'only the load the test itself did');
    });

    test('fetches once when nothing is loaded yet, then matches', () async {
      final service = _FakeStoriesService(remote: [storyWith(7, 'calm')]);
      final provider = StoriesProvider(service);
      expect(provider.myStories, isEmpty);

      final story = await PracticeEntry.resolveStory(provider, 'calm');

      expect(story?.id, 7);
      expect(service.fetchCount, 1);
    });

    test('matches regardless of case', () async {
      final service = _FakeStoriesService(remote: [storyWith(3, 'Calm')]);
      final provider = StoriesProvider(service);

      final story = await PracticeEntry.resolveStory(provider, 'calm');

      expect(story?.id, 3);
    });

    test('answers null when the user has no story for the word', () async {
      final service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
      final provider = StoriesProvider(service);

      final story = await PracticeEntry.resolveStory(provider, 'calm');

      expect(story, isNull);
      expect(service.fetchCount, 1);
    });

    test(
      'does not fetch again when the list is loaded and has no match',
      () async {
        final service = _FakeStoriesService(remote: [storyWith(1, 'river')]);
        final provider = StoriesProvider(service);
        await provider.fetchMyStories();
        expect(service.fetchCount, 1);

        final story = await PracticeEntry.resolveStory(provider, 'calm');

        expect(story, isNull);
        expect(service.fetchCount, 1, reason: 'the list is already loaded');
      },
    );

    test('allowFetch false never reaches the network', () async {
      final service = _FakeStoriesService(remote: [storyWith(1, 'calm')]);
      final provider = StoriesProvider(service);

      final story = await PracticeEntry.resolveStory(
        provider,
        'calm',
        allowFetch: false,
      );

      expect(story, isNull);
      expect(service.fetchCount, 0);
    });
  });
}
