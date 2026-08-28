import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test double over the real service: only the methods the controller uses are
/// overridden, so the controller is exercised against the actual API surface.
class _FakeTtsService extends TtsService {
  bool supported = true;
  List<String> languages = ['en-US', 'zh-CN'];
  bool languageAvailable = true;
  bool pauseSucceeds = true;

  final List<String> spoken = [];
  final List<double> rates = [];
  int stopCount = 0;
  int pauseCount = 0;

  /// Outcome for each utterance, in order; the last value repeats.
  List<TtsSpeakOutcome> outcomes = [TtsSpeakOutcome.completed];

  /// When true, every `speakAndWait` hangs until the test releases its gate,
  /// so playback can be inspected mid-utterance.
  bool gateUtterances = false;

  /// One gate per gated utterance, in call order.
  final List<Completer<void>> gates = [];

  @override
  bool get isSupported => supported;

  @override
  Future<List<String>> getLanguages() async => languages;

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      languageAvailable;

  @override
  Future<void> setSpeechRateMultiplier(double multiplier) async {
    rates.add(multiplier);
  }

  @override
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    final index = spoken.length;
    spoken.add(text);

    if (gateUtterances) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }

    return index < outcomes.length ? outcomes[index] : outcomes.last;
  }

  /// When set, `stop` and `pause` hang until the test releases them, so a new
  /// playback can begin while an earlier control call is still in flight.
  Completer<void>? holdStop;
  Completer<void>? holdPause;

  @override
  Future<void> stop() async {
    stopCount++;
    if (holdStop != null) await holdStop!.future;
  }

  @override
  Future<bool> pause() async {
    pauseCount++;
    if (holdPause != null) await holdPause!.future;
    return pauseSucceeds;
  }

  /// Release the gate for utterance [index], letting it return its outcome.
  void release(int index) {
    if (!gates[index].isCompleted) gates[index].complete();
  }

  /// Release every gate opened so far, newest last.
  void releaseAll() {
    for (var i = 0; i < gates.length; i++) {
      release(i);
    }
  }
}

void main() {
  // FlutterTts registers a method-call handler in its constructor, so the real
  // TtsService the fake extends needs an initialized binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const content = 'First sentence. Second sentence. Third sentence.';

  late _FakeTtsService tts;

  StoryAudioController build({String? storyContent}) {
    return StoryAudioController.forContent(
      ttsService: tts,
      languageCode: 'en',
      content: storyContent ?? content,
    );
  }

  setUp(() {
    tts = _FakeTtsService();
    SharedPreferences.setMockInitialValues({});
  });

  test('segments the story content into sentences', () {
    final controller = build();
    expect(controller.sentences.length, 3);
    expect(controller.sentences.first.speakable, 'First sentence.');
    controller.dispose();
  });

  test(
    'a sentence with nothing to speak is skipped, not treated as failure',
    () async {
      // The segmenter avoids emitting such spans, but the controller is the
      // shared entry point for the listening features too: an unspeakable span
      // must not end the story.
      final controller = StoryAudioController(
        ttsService: tts,
        languageCode: 'en',
        sentences: const [
          SentenceSpan(start: 0, end: 2, raw: '\n\n'),
          SentenceSpan(start: 2, end: 18, raw: 'A real sentence.'),
        ],
      );
      await controller.prepare();
      await controller.play();

      expect(tts.spoken, ['A real sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    },
  );

  group('a slow control call cannot reach into the playback that replaced it', () {
    test(
      'a refused pause returning late does not stop the new sentence',
      () async {
        // The stop fallback for a refused pause is the dangerous one: by the time
        // it runs, the user may have tapped a different sentence.
        tts.pauseSucceeds = false;
        tts.gateUtterances = true;
        final controller = build();
        await controller.prepare();

        unawaited(controller.play());
        await pumpEventQueue();

        tts.holdPause = Completer<void>();
        final pausing = controller.pause();
        await pumpEventQueue();

        // The user taps sentence 2 while the pause is still in flight.
        unawaited(controller.playSentence(2));
        await pumpEventQueue();
        expect(tts.spoken.last, 'Third sentence.');

        final stopsBefore = tts.stopCount;
        tts.holdPause!.complete();
        await pausing;
        await pumpEventQueue();

        expect(
          tts.stopCount,
          stopsBefore,
          reason: 'the refused pause must not stop the new sentence',
        );
        expect(controller.state, StoryPlaybackState.playing);
        expect(controller.currentIndex, 2);

        controller.dispose();
      },
    );

    test(
      'a successful pause returning late leaves the new sentence playing',
      () async {
        tts.gateUtterances = true;
        final controller = build();
        await controller.prepare();

        unawaited(controller.play());
        await pumpEventQueue();

        tts.holdPause = Completer<void>();
        final pausing = controller.pause();
        await pumpEventQueue();

        unawaited(controller.playSentence(1));
        await pumpEventQueue();

        tts.holdPause!.complete();
        await pausing;
        await pumpEventQueue();

        expect(controller.state, StoryPlaybackState.playing);
        expect(controller.currentIndex, 1);

        controller.dispose();
      },
    );

    test(
      'a stop returning late does not end the playback started after it',
      () async {
        tts.gateUtterances = true;
        final controller = build();
        await controller.prepare();

        unawaited(controller.play());
        await pumpEventQueue();

        tts.holdStop = Completer<void>();
        final stopping = controller.stop();
        await pumpEventQueue();
        expect(controller.state, StoryPlaybackState.idle);

        // The user immediately plays again while that stop is still in flight.
        unawaited(controller.play());
        await pumpEventQueue();
        expect(controller.state, StoryPlaybackState.playing);

        tts.holdStop!.complete();
        await stopping;
        await pumpEventQueue();

        expect(
          controller.state,
          StoryPlaybackState.playing,
          reason: 'the earlier stop must not idle the new playback',
        );
        expect(controller.currentIndex, 0);

        controller.dispose();
      },
    );
  });

  group('prepare', () {
    test('is available when the platform and voices support it', () async {
      final controller = build();
      await controller.prepare();

      expect(controller.isAvailable, isTrue);
      expect(controller.languageMissing, isFalse);
      controller.dispose();
    });

    test('unavailable when the platform has no TTS', () async {
      tts.supported = false;
      final controller = build();
      await controller.prepare();

      expect(controller.isAvailable, isFalse);
      expect(
        controller.unavailableReason,
        StoryAudioUnavailableReason.platformUnsupported,
      );
      controller.dispose();
    });

    test('unavailable when no voices are installed', () async {
      tts.languages = [];
      final controller = build();
      await controller.prepare();

      expect(controller.isAvailable, isFalse);
      expect(
        controller.unavailableReason,
        StoryAudioUnavailableReason.noVoices,
      );
      controller.dispose();
    });

    test('unavailable for an empty story', () async {
      final controller = build(storyContent: '   ');
      await controller.prepare();

      expect(controller.isAvailable, isFalse);
      expect(
        controller.unavailableReason,
        StoryAudioUnavailableReason.emptyStory,
      );
      controller.dispose();
    });

    test('flags a missing voice for the story language', () async {
      tts.languageAvailable = false;
      final controller = build();
      await controller.prepare();

      expect(controller.isAvailable, isTrue);
      expect(controller.languageMissing, isTrue);
      controller.dispose();
    });
  });

  group('sequential playback', () {
    test('speaks every sentence in order then returns to idle', () async {
      final controller = build();
      await controller.prepare();
      await controller.play();

      expect(tts.spoken, [
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      expect(controller.state, StoryPlaybackState.idle);
      expect(controller.currentIndex, -1);
      controller.dispose();
    });

    test('stops advancing when an utterance is cancelled', () async {
      tts.outcomes = [TtsSpeakOutcome.completed, TtsSpeakOutcome.cancelled];
      final controller = build();
      await controller.prepare();
      await controller.play();

      expect(tts.spoken, ['First sentence.', 'Second sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test('stops advancing when an utterance errors', () async {
      tts.outcomes = [TtsSpeakOutcome.error];
      final controller = build();
      await controller.prepare();
      await controller.play();

      expect(tts.spoken, ['First sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test('playFrom starts at the given sentence', () async {
      final controller = build();
      await controller.prepare();
      await controller.playFrom(1);

      expect(tts.spoken, ['Second sentence.', 'Third sentence.']);
      controller.dispose();
    });

    test('does nothing when unavailable', () async {
      tts.supported = false;
      final controller = build();
      await controller.prepare();
      await controller.play();

      expect(tts.spoken, isEmpty);
      controller.dispose();
    });

    test('highlights the sentence being spoken', () async {
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.play();
      await pumpEventQueue();

      expect(controller.currentIndex, 0);
      expect(controller.isPlaying, isTrue);

      tts.gateUtterances = false;
      tts.releaseAll();
      await playback;
      expect(controller.currentIndex, -1);
      controller.dispose();
    });
  });

  group('single sentence playback', () {
    test('speaks only the tapped sentence', () async {
      final controller = build();
      await controller.prepare();
      await controller.playSentence(2);

      expect(tts.spoken, ['Third sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test('ignores an out-of-range index', () async {
      final controller = build();
      await controller.prepare();
      await controller.playSentence(9);

      expect(tts.spoken, isEmpty);
      controller.dispose();
    });

    test(
      'a superseded utterance neither advances nor clears newer state',
      () async {
        final controller = build();
        await controller.prepare();

        // First tap hangs mid-utterance.
        tts.gateUtterances = true;
        final first = controller.playSentence(0);
        await pumpEventQueue();

        // Second tap supersedes it while the first is still in flight.
        final second = controller.playSentence(1);
        await pumpEventQueue();

        expect(tts.spoken, ['First sentence.', 'Second sentence.']);
        expect(controller.currentIndex, 1);

        // The stale first utterance now returns: it must not reset the state
        // that the second tap owns.
        tts.release(0);
        await first;
        expect(controller.currentIndex, 1);
        expect(controller.isPlaying, isTrue);

        tts.release(1);
        await second;
        expect(controller.state, StoryPlaybackState.idle);
        expect(controller.currentIndex, -1);
        controller.dispose();
      },
    );
  });

  group('pause, resume and stop', () {
    test('pause keeps the sentence and resume continues from it', () async {
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.play();
      await pumpEventQueue();

      await controller.pause();
      expect(controller.isPaused, isTrue);
      expect(controller.currentIndex, 0);
      expect(tts.pauseCount, 1);

      tts.gateUtterances = false;
      tts.releaseAll();
      await playback;
      // The paused utterance was superseded, so playback did not advance.
      expect(tts.spoken, ['First sentence.']);
      expect(controller.isPaused, isTrue);

      await controller.resume();
      expect(tts.spoken.sublist(1), [
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test('falls back to stop when the platform refuses to pause', () async {
      tts.pauseSucceeds = false;
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.play();
      await pumpEventQueue();

      await controller.pause();
      expect(tts.stopCount, 1);
      expect(controller.isPaused, isTrue);

      tts.gateUtterances = false;
      tts.releaseAll();
      await playback;
      controller.dispose();
    });

    test('stop clears state and highlight', () async {
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.play();
      await pumpEventQueue();

      await controller.stop();
      expect(controller.state, StoryPlaybackState.idle);
      expect(controller.currentIndex, -1);
      expect(tts.stopCount, 1);

      tts.gateUtterances = false;
      tts.releaseAll();
      await playback;
      expect(tts.spoken, ['First sentence.']);
      controller.dispose();
    });

    test('dispose stops the shared service without disposing it', () async {
      final controller = build();
      await controller.prepare();
      controller.dispose();

      expect(tts.stopCount, 1);
    });
  });

  group('rate', () {
    test('applies the rate before each playback run', () async {
      final controller = build();
      await controller.prepare();

      await controller.setRate(1.25);
      await controller.play();
      await controller.playSentence(0);

      expect(controller.rate, 1.25);
      // Once for the idle setRate, then before the two playback runs.
      expect(tts.rates, [1.25, 1.25, 1.25]);
      controller.dispose();
    });

    test('restarts the current sentence when changed mid-playback', () async {
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.play();
      await pumpEventQueue();
      expect(tts.spoken, ['First sentence.']);

      tts.gateUtterances = false;
      final restarted = controller.setRate(0.75);
      tts.releaseAll();
      await playback;
      await restarted;

      expect(controller.rate, 0.75);
      expect(tts.rates, [1.0, 0.75]);
      // Sentence 0 is spoken again under the new rate, then the story runs on.
      expect(tts.spoken, [
        'First sentence.',
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      controller.dispose();
    });

    test('rate options run from 0.5x up to 1.25x', () {
      expect(StoryAudioController.rateOptions, [0.5, 0.6, 0.75, 1.0, 1.25]);
    });

    test(
      'a rate change during one sentence does not read on into the story',
      () async {
        // The practice modes play a single reference sentence and then change the
        // rate: restarting it as a full read would speak the next exercise's
        // answer.
        final controller = build();
        await controller.prepare();

        tts.gateUtterances = true;
        final playback = controller.playSentence(1);
        await pumpEventQueue();

        tts.gateUtterances = false;
        final restarted = controller.setRate(0.75);
        tts.releaseAll();
        await playback;
        await restarted;

        expect(tts.spoken, ['Second sentence.', 'Second sentence.']);
        expect(controller.state, StoryPlaybackState.idle);
        controller.dispose();
      },
    );
  });

  group('remembered rate', () {
    test('restores the rate chosen in an earlier story', () async {
      SharedPreferences.setMockInitialValues({'story_playback_rate': 0.5});
      final controller = build();
      await controller.prepare();

      expect(controller.rate, 0.5);
      controller.dispose();
    });

    test('ignores a stored rate no longer on offer', () async {
      SharedPreferences.setMockInitialValues({'story_playback_rate': 0.9});
      final controller = build();
      await controller.prepare();

      expect(controller.rate, 1.0);
      controller.dispose();
    });

    test('ignores a stored value of the wrong type', () async {
      // `getDouble` is a typed cast, so this throws inside the adapter rather
      // than reading as null.
      SharedPreferences.setMockInitialValues({'story_playback_rate': 'fast'});
      final controller = build();
      await controller.prepare();

      expect(controller.rate, 1.0);
      controller.dispose();
    });

    test('persists the chosen rate', () async {
      final controller = build();
      await controller.prepare();

      await controller.setRate(0.6);
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('story_playback_rate'), 0.6);
      controller.dispose();
    });

    test('a rate chosen while the restore is in flight wins', () async {
      SharedPreferences.setMockInitialValues({'story_playback_rate': 0.5});
      final controller = build();

      final prepared = controller.prepare();
      await controller.setRate(0.75);
      await prepared;

      expect(controller.rate, 0.75);
      controller.dispose();
    });

    test(
      'choosing the rate already showing still beats a pending restore',
      () async {
        // The setter short-circuits on an unchanged value, so the suppression
        // has to be recorded before that early return.
        SharedPreferences.setMockInitialValues({'story_playback_rate': 0.5});
        final controller = build();

        final prepared = controller.prepare();
        await controller.setRate(1.0);
        await prepared;
        await pumpEventQueue();

        expect(controller.rate, 1.0);
        // ...and it is what gets remembered: the setter's early return must
        // not leave the replaced 0.5x in storage.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('story_playback_rate'), 1.0);
        controller.dispose();

        final next = build();
        await next.prepare();
        expect(next.rate, 1.0);
        next.dispose();
      },
    );
  });

  group('auto-repeat', () {
    test('defaults to speaking each sentence once', () async {
      final controller = build();
      await controller.prepare();
      await controller.play();

      expect(controller.repeatCount, 1);
      expect(tts.spoken, [
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      controller.dispose();
    });

    test('speaks each sentence twice before advancing', () async {
      final controller = build();
      await controller.prepare();
      controller.setRepeatCount(2);
      await controller.play();

      expect(tts.spoken, [
        'First sentence.',
        'First sentence.',
        'Second sentence.',
        'Second sentence.',
        'Third sentence.',
        'Third sentence.',
      ]);
      controller.dispose();
    });

    test('repeats a single sentence without moving on', () async {
      final controller = build();
      await controller.prepare();
      controller.setRepeatCount(2);
      await controller.playSentence(1);

      expect(tts.spoken, ['Second sentence.', 'Second sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test(
      'a change mid-run lands on the next sentence, not the current one',
      () async {
        final controller = build();
        await controller.prepare();

        tts.gateUtterances = true;
        final playback = controller.play();
        await pumpEventQueue();
        expect(tts.spoken, ['First sentence.']);

        // Changed while sentence 0 is speaking: sentence 0 keeps the count it
        // started with, sentence 1 gets the new one.
        controller.setRepeatCount(2);
        tts.gateUtterances = false;
        tts.releaseAll();
        await playback;

        expect(tts.spoken, [
          'First sentence.',
          'Second sentence.',
          'Second sentence.',
          'Third sentence.',
          'Third sentence.',
        ]);
        controller.dispose();
      },
    );

    test('a stop during a repeat cancels the remaining passes', () async {
      final controller = build();
      await controller.prepare();
      controller.setRepeatCount(2);

      tts.gateUtterances = true;
      final playback = controller.playSentence(0);
      await pumpEventQueue();
      expect(tts.spoken, ['First sentence.']);

      await controller.stop();
      tts.releaseAll();
      await playback;
      await pumpEventQueue();

      expect(tts.spoken, ['First sentence.']);
      expect(controller.state, StoryPlaybackState.idle);
      controller.dispose();
    });

    test('is clamped to the offered options', () {
      final controller = build();
      controller.setRepeatCount(7);
      expect(controller.repeatCount, 2);
      controller.setRepeatCount(0);
      expect(controller.repeatCount, 1);
      expect(StoryAudioController.repeatOptions, [1, 2]);
      controller.dispose();
    });
  });

  group('auto-advance', () {
    test(
      'a sentence played with advance runs to the end of the story',
      () async {
        final controller = build();
        await controller.prepare();
        await controller.playSentence(1, advance: true);

        expect(tts.spoken, ['Second sentence.', 'Third sentence.']);
        controller.dispose();
      },
    );

    test('defaults off, so a sentence stops where it started', () async {
      final controller = build();
      await controller.prepare();
      expect(controller.autoAdvance, false);

      await controller.playSentence(1, advance: controller.autoAdvance);

      expect(tts.spoken, ['Second sentence.']);
      controller.dispose();
    });

    test('the toggle a run started with is the one it keeps', () async {
      // The flag is a snapshot of the call, not a live read: turning
      // auto-advance on mid-sentence must not extend the run in flight.
      final controller = build();
      await controller.prepare();

      tts.gateUtterances = true;
      final playback = controller.playSentence(0, advance: false);
      await pumpEventQueue();

      controller.setAutoAdvance(true);
      tts.gateUtterances = false;
      tts.releaseAll();
      await playback;

      expect(tts.spoken, ['First sentence.']);
      expect(controller.autoAdvance, true);

      // The next call picks the new value up.
      await controller.playSentence(1, advance: controller.autoAdvance);
      expect(tts.spoken, [
        'First sentence.',
        'Second sentence.',
        'Third sentence.',
      ]);
      controller.dispose();
    });

    test(
      'resume continues the run it belongs to, not the whole story',
      () async {
        final controller = build();
        await controller.prepare();

        tts.gateUtterances = true;
        final playback = controller.playSentence(1, advance: false);
        await pumpEventQueue();

        await controller.pause();
        tts.gateUtterances = false;
        tts.releaseAll();
        await playback;
        expect(controller.isPaused, true);

        await controller.resume();

        expect(tts.spoken, ['Second sentence.', 'Second sentence.']);
        expect(controller.state, StoryPlaybackState.idle);
        controller.dispose();
      },
    );

    test(
      'repeat and advance combine: twice each, all the way through',
      () async {
        final controller = build();
        await controller.prepare();
        controller.setRepeatCount(2);
        controller.setAutoAdvance(true);

        await controller.playSentence(1, advance: controller.autoAdvance);

        expect(tts.spoken, [
          'Second sentence.',
          'Second sentence.',
          'Third sentence.',
          'Third sentence.',
        ]);
        controller.dispose();
      },
    );
  });

  group('prepare settles', () {
    test('isPrepared is set once the probe has an answer', () async {
      final controller = build();
      expect(controller.isPrepared, false);
      await controller.prepare();
      expect(controller.isPrepared, true);
      controller.dispose();
    });

    test('an unfavourable probe still counts as settled', () async {
      tts.supported = false;
      final controller = build();
      await controller.prepare();

      expect(controller.isPrepared, true);
      expect(controller.isAvailable, false);
      controller.dispose();
    });
  });
}
