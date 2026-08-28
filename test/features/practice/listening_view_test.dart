import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/presentation/listening_view.dart';
import 'package:new_words/features/practice/utils/listening_set_builder.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A TTS service that never touches a platform channel: what the view asked to
/// speak, and how often, is what the assertions read.
class _FakeTtsService extends TtsService {
  _FakeTtsService({
    this.supported = true,
    this.availableLanguages = const ['en-US'],
    this.languageAvailable = true,
  });

  final bool supported;
  final List<String> availableLanguages;
  final bool languageAvailable;

  final List<String> spoken = [];
  int stopCount = 0;

  /// Holds each utterance open, so a test can tap Replay mid-playback.
  bool hold = false;
  final List<Completer<TtsSpeakOutcome>> pending = [];

  @override
  bool get isSupported => supported;

  @override
  Future<void> init({String? language}) async {}

  @override
  Future<List<String>> getLanguages() async => availableLanguages;

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      languageAvailable;

  @override
  Future<void> setSpeechRateMultiplier(double multiplier) async {}

  @override
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    spoken.add(text);
    if (!hold) return TtsSpeakOutcome.completed;
    final completer = Completer<TtsSpeakOutcome>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<bool> pause() async => true;

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

void main() {
  // The story audio controller restores the remembered speech rate from
  // preferences on prepare(); give it a deterministic empty store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const dictationStory =
      'The morning air was cold and clean. '
      'She walked to the river without speaking.';

  const clozeStory =
      'He was **running** through the park at dawn. '
      'The morning air was cold and clean.';

  Story storyWith(String content, {String language = 'en'}) => Story(
    id: 1,
    userId: 1,
    content: content,
    storyWords: 'run',
    learningLanguage: language,
    firstReadAt: 1700000000,
    favoriteCount: 0,
    createdAt: 1700000000,
  );

  /// Hosts the view the way `StoryDetailScreen` does: one controller and one
  /// exercise set, both owned outside the view and prepared before it mounts.
  Future<StoryAudioController> pumpScreen(
    WidgetTester tester,
    Story story,
    _FakeTtsService tts, {

    /// False while an utterance is held open: the playing indicator animates
    /// forever, so pumpAndSettle would never return.
    bool settle = true,
  }) async {
    final audio = StoryAudioController.forContent(
      ttsService: tts,
      languageCode: story.learningLanguage,
      content: story.content,
    );
    await audio.prepare();
    addTearDown(audio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListeningView(
            story: story,
            audio: audio,
            items: ListeningSetBuilder.build(
              languageCode: story.learningLanguage,
              sentences: audio.sentences,
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    return audio;
  }

  /// Taps a button by its label, scrolling it into view first: the exercise
  /// column is taller than the test viewport.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('exercise flow', () {
    testWidgets('plays the first item with its text hidden', (tester) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);

      expect(find.text('1 / 2'), findsOneWidget);
      expect(tts.spoken, ['The morning air was cold and clean.']);
      // The sentence itself must not be on screen before it is checked.
      expect(find.text('The morning air was cold and clean.'), findsNothing);
      expect(find.text('Play'), findsNothing);
      expect(find.text('Replay'), findsOneWidget);
    });

    testWidgets('Check scores the typed answer and reveals the reference', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);

      await tester.enterText(
        find.byType(TextField),
        'the morning air was cold and clean',
      );
      await tapButton(tester, 'Check');

      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('The morning air was cold and clean.'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a wrong answer reports a failure and can be retried', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);

      await tester.enterText(find.byType(TextField), 'nothing like that');
      await tapButton(tester, 'Check');
      expect(find.text('Not quite'), findsOneWidget);

      await tapButton(tester, 'Retry');

      // Retry re-hides the sentence and clears the input.
      expect(find.text('Not quite'), findsNothing);
      expect(find.text('The morning air was cold and clean.'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('Show answer reveals without scoring', (tester) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);

      await tapButton(tester, 'Show answer');

      expect(find.text('Answer shown'), findsOneWidget);
      expect(find.text('The morning air was cold and clean.'), findsWidgets);
    });

    testWidgets('advancing plays the next sentence and finishes the set', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);

      await tapButton(tester, 'Show answer');
      await tapButton(tester, 'Next');

      expect(find.text('2 / 2'), findsOneWidget);
      expect(tts.spoken.last, 'She walked to the river without speaking.');

      await tapButton(tester, 'Show answer');
      // The last item's advance button says Finish, not Next.
      expect(find.text('Next'), findsNothing);
      await tapButton(tester, 'Finish');

      expect(find.text('Set complete'), findsOneWidget);
      expect(find.text('Correct: 0 / 2'), findsOneWidget);
    });

    testWidgets('rapid Replay never leaves two utterances running', (
      tester,
    ) async {
      final tts = _FakeTtsService()..hold = true;
      await pumpScreen(tester, storyWith(dictationStory), tts, settle: false);

      final replay = find.text('Replay');
      await tester.tap(replay);
      await tester.pump();
      await tester.tap(replay);
      await tester.pump();

      // Three requests were issued, all for the same sentence — never two
      // different ones at once — and the two superseded utterances are
      // invalidated by the controller's generation guard, so completing them
      // cannot resume playback or advance the item.
      expect(tts.spoken, [
        'The morning air was cold and clean.',
        'The morning air was cold and clean.',
        'The morning air was cold and clean.',
      ]);
      for (final completer in tts.pending) {
        completer.complete(TtsSpeakOutcome.completed);
      }
      await tester.pump();
      expect(tts.spoken.length, 3);
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('cloze', () {
    testWidgets('shows the sentence with the marked span blanked', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(clozeStory), tts);

      expect(find.text('Listen and type the missing word'), findsOneWidget);
      expect(find.textContaining('_____'), findsOneWidget);
      // The blanked word is nowhere on screen, and no marker leaked.
      expect(find.textContaining('running'), findsNothing);
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('accepts the inflected form the story used', (tester) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(clozeStory), tts);

      await tester.enterText(find.byType(TextField), 'Running');
      await tapButton(tester, 'Check');

      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('rejects the saved lemma the story did not use', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(clozeStory), tts);

      await tester.enterText(find.byType(TextField), 'run');
      await tapButton(tester, 'Check');

      expect(find.text('Correct'), findsNothing);
    });
  });

  group('unavailable', () {
    testWidgets('explains an unsupported platform and speaks nothing', (
      tester,
    ) async {
      final tts = _FakeTtsService(supported: false);
      await pumpScreen(tester, storyWith(dictationStory), tts);

      expect(find.textContaining('does not support'), findsOneWidget);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('explains a device with no installed voice', (tester) async {
      final tts = _FakeTtsService(availableLanguages: const []);
      await pumpScreen(tester, storyWith(dictationStory), tts);

      expect(
        find.textContaining('No text-to-speech voice is installed'),
        findsOneWidget,
      );
      expect(tts.spoken, isEmpty);
    });

    testWidgets('disables the mode when the story language has no voice', (
      tester,
    ) async {
      final tts = _FakeTtsService(languageAvailable: false);
      await pumpScreen(tester, storyWith(dictationStory), tts);

      expect(
        find.textContaining("No voice is installed for this story's language"),
        findsOneWidget,
      );
      expect(tts.spoken, isEmpty);
    });

    testWidgets('shows an empty state for a story with no usable sentence', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith('Go now.'), tts);

      expect(find.textContaining('no sentence long enough'), findsOneWidget);
      expect(tts.spoken, isEmpty);
    });
  });

  group('the host owns the controller', () {
    testWidgets('leaving the mode stops audio', (tester) async {
      final tts = _FakeTtsService();
      await pumpScreen(tester, storyWith(dictationStory), tts);
      final before = tts.stopCount;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(before));
    });

    testWidgets('the shared controller is stopped, never disposed', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      final audio = await pumpScreen(tester, storyWith(dictationStory), tts);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // A disposed ChangeNotifier throws on use; the host must still be able to
      // read from and drive its own controller after a mode goes away.
      expect(audio.sentences, isNotEmpty);
      await audio.playSentence(0);
      expect(tts.spoken.last, 'The morning air was cold and clean.');
    });

    testWidgets('reference playback honours auto-repeat and never runs on', (
      tester,
    ) async {
      final tts = _FakeTtsService();
      final audio = await pumpScreen(tester, storyWith(dictationStory), tts);
      // The first item played on mount; the repeat setting arrives from Read.
      audio.setRepeatCount(2);
      tts.spoken.clear();

      await tapButton(tester, 'Replay');

      expect(tts.spoken, [
        'The morning air was cold and clean.',
        'The morning air was cold and clean.',
      ]);
    });
  });
}
