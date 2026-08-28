import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_words/common/constants/storage_keys.dart';

/// The voice the learner picked, as it was stored.
///
/// The locale is kept alongside the name because a voice name only means
/// something for the locale it belongs to: after the learning language changes,
/// a remembered `en-US` voice must not be applied to `zh-CN`.
class StoredTtsVoice {
  final String name;
  final String locale;

  const StoredTtsVoice({required this.name, required this.locale});
}

/// Stores the read-aloud voice the learner last chose.
///
/// Mirrors `StoryPlaybackPrefs`: the only place voice selection touches
/// [SharedPreferences], and every method swallows its own failures. Playback
/// must never depend on storage working, so an unreadable or unwritable
/// preference degrades to "no remembered voice" — which is the automatic pick —
/// rather than to an error the service has to handle.
///
/// The stored pair is a plain name/locale, not an engine- or device-specific
/// handle, so a future server-side voice list can reuse this same setting.
class TtsVoicePrefs {
  const TtsVoicePrefs();

  /// The remembered voice, or null when there is none.
  ///
  /// A half-written pair (name without locale, or the reverse) reads as null:
  /// neither half is usable on its own.
  Future<StoredTtsVoice?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(StorageKeys.ttsVoiceName);
      final locale = prefs.getString(StorageKeys.ttsVoiceLocale);
      if (name == null || locale == null) return null;
      if (name.isEmpty || locale.isEmpty) return null;
      return StoredTtsVoice(name: name, locale: locale);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(StoredTtsVoice voice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageKeys.ttsVoiceName, voice.name);
      await prefs.setString(StorageKeys.ttsVoiceLocale, voice.locale);
    } catch (_) {
      // Best-effort: the voice still applies to this session.
    }
  }

  /// Forgets the choice, returning the device to the automatic pick.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.ttsVoiceName);
      await prefs.remove(StorageKeys.ttsVoiceLocale);
    } catch (_) {
      // Best-effort: automatic selection resumes next launch at the latest.
    }
  }
}
