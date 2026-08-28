import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/common/constants/storage_keys.dart';
import 'package:new_words/services/tts_voice_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prefs = TtsVoicePrefs();

  test('a saved voice reads back as the same name and locale', () async {
    SharedPreferences.setMockInitialValues({});

    await prefs.save(
      const StoredTtsVoice(name: 'en-us-x-sfg#male_1', locale: 'en-US'),
    );

    final stored = await prefs.load();
    expect(stored?.name, 'en-us-x-sfg#male_1');
    expect(stored?.locale, 'en-US');
  });

  test('nothing stored reads as no choice', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await prefs.load(), isNull);
  });

  test('clear forgets the choice, returning the device to automatic', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.ttsVoiceName: 'basic',
      StorageKeys.ttsVoiceLocale: 'en-US',
    });

    await prefs.clear();

    expect(await prefs.load(), isNull);
  });

  test('half a pair is not a usable choice', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.ttsVoiceName: 'basic'});
    expect(await prefs.load(), isNull);

    SharedPreferences.setMockInitialValues({
      StorageKeys.ttsVoiceLocale: 'en-US',
    });
    expect(await prefs.load(), isNull);
  });

  test(
    'a wrong-typed stored value degrades to no choice, not an error',
    () async {
      // `getString` is a typed cast and throws when something else was written
      // under the key, which is what the adapter has to swallow.
      SharedPreferences.setMockInitialValues({
        StorageKeys.ttsVoiceName: 42,
        StorageKeys.ttsVoiceLocale: 'en-US',
      });

      expect(await prefs.load(), isNull);
    },
  );

  test('an empty stored name is not a usable choice', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.ttsVoiceName: '',
      StorageKeys.ttsVoiceLocale: 'en-US',
    });

    expect(await prefs.load(), isNull);
  });
}
