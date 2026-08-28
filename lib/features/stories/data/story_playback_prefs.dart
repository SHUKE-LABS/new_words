import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_words/common/constants/storage_keys.dart';

/// Stores the story playback speed the learner last chose.
///
/// The only place the stories feature touches [SharedPreferences]: the audio
/// controller talks to this instead of holding a preferences key of its own.
///
/// Both methods swallow their own failures. Playback must never depend on
/// storage working, so an unreadable or unwritable preference degrades to "no
/// remembered rate" rather than to an error the controller has to handle.
class StoryPlaybackPrefs {
  const StoryPlaybackPrefs();

  /// The remembered speech-rate multiplier, or null when there is none.
  ///
  /// `getDouble` is a typed cast and throws when something else was written
  /// under the key, so a wrong-typed value reads as null.
  Future<double?> loadRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(StorageKeys.storyPlaybackRate);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRate(double multiplier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(StorageKeys.storyPlaybackRate, multiplier);
    } catch (_) {
      // Best-effort: the rate still applies to this session.
    }
  }
}
