import 'package:new_words/entities/story.dart';
import 'package:new_words/features/stories/utils/story_utils.dart';
import 'package:new_words/providers/stories_provider.dart';

/// Finds the story to practise a single vocabulary word with.
///
/// Separate from the screen because the branching — already loaded, never
/// loaded, nothing matching — is the part worth testing without a widget tree.
class PracticeEntry {
  const PracticeEntry._();

  /// The user's own story containing [word], or null when they have none.
  ///
  /// The story list is fetched once when it is empty: the Stories tab is lazy,
  /// so a user who has only ever opened the word list has no stories in memory
  /// even when the server has plenty. An empty list after that fetch means
  /// there is genuinely nothing to practise with.
  static Future<Story?> resolveStory(
    StoriesProvider provider,
    String word, {
    bool allowFetch = true,
  }) async {
    final match = _match(provider.myStories, word);
    if (match != null) return match;

    if (allowFetch && provider.myStories.isEmpty) {
      await provider.fetchMyStories();
      return _match(provider.myStories, word);
    }
    return null;
  }

  static Story? _match(List<Story> stories, String word) {
    for (final story in stories) {
      if (StoryUtils.containsVocabulary(story, [word])) return story;
    }
    return null;
  }
}
