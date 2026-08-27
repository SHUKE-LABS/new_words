import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';
import 'package:new_words/services/tts_service.dart';

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

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<bool> pause() async {
    pauseCount++;
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
  });

  test('segments the story content into sentences', () {
    final controller = build();
    expect(controller.sentences.length, 3);
    expect(controller.sentences.first.speakable, 'First sentence.');
    controller.dispose();
  });

  test('a sentence with nothing to speak is skipped, not treated as failure',
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

    test('a superseded utterance neither advances nor clears newer state',
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
    });
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

    test('rate options include 0.75x, 1.0x and 1.25x', () {
      expect(StoryAudioController.rateOptions, [0.75, 1.0, 1.25]);
    });
  });
}
