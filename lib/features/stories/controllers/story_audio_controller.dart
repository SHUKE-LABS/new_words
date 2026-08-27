import 'package:flutter/foundation.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';
import 'package:new_words/services/tts_service.dart';

enum StoryPlaybackState { idle, playing, paused }

/// Why read-aloud is unavailable, so the UI can explain it.
enum StoryAudioUnavailableReason {
  /// The platform has no TTS at all (Linux, and Web where `Platform` throws).
  platformUnsupported,

  /// TTS exists but reports no installed voices.
  noVoices,

  /// The story has no sentences to read.
  emptyStory,
}

/// Drives sentence-by-sentence read-aloud of one story.
///
/// Owns playback state for [StoryDetailScreen] and is the single entry point
/// for the story-audio features layered on top of this one, so they never talk
/// to [TtsService] directly.
///
/// [TtsService] is a shared GetIt singleton also used by word detail, so this
/// controller only ever calls [TtsService.stop] — never `dispose()`.
class StoryAudioController extends ChangeNotifier {
  final TtsService _tts;
  final String languageCode;
  final List<SentenceSpan> sentences;

  StoryAudioController({
    required TtsService ttsService,
    required this.languageCode,
    required this.sentences,
  }) : _tts = ttsService;

  factory StoryAudioController.forContent({
    required TtsService ttsService,
    required String languageCode,
    required String content,
  }) {
    return StoryAudioController(
      ttsService: ttsService,
      languageCode: languageCode,
      sentences: SentenceSegmenter.segment(content),
    );
  }

  static const List<double> rateOptions = [0.75, 1.0, 1.25];

  StoryPlaybackState _state = StoryPlaybackState.idle;
  int _currentIndex = -1;
  double _rate = 1.0;
  bool _isAvailable = true;
  StoryAudioUnavailableReason? _unavailableReason;
  bool _languageMissing = false;
  bool _disposed = false;

  /// Invalidates in-flight utterances: every state-changing entry point bumps
  /// it, so a completion arriving from a superseded utterance is ignored. This
  /// is what keeps rapid taps from overlapping audio.
  int _generation = 0;

  StoryPlaybackState get state => _state;
  int get currentIndex => _currentIndex;
  double get rate => _rate;
  bool get isAvailable => _isAvailable;
  StoryAudioUnavailableReason? get unavailableReason => _unavailableReason;

  /// True when TTS works but no voice is installed for [languageCode].
  bool get languageMissing => _languageMissing;

  bool get isPlaying => _state == StoryPlaybackState.playing;
  bool get isPaused => _state == StoryPlaybackState.paused;
  bool get hasSentences => sentences.isNotEmpty;

  /// Probes platform support and voice availability. Safe to call once from
  /// `initState`.
  Future<void> prepare() async {
    if (sentences.isEmpty) {
      _setUnavailable(StoryAudioUnavailableReason.emptyStory);
      return;
    }

    if (!_tts.isSupported) {
      _setUnavailable(StoryAudioUnavailableReason.platformUnsupported);
      return;
    }

    final languages = await _tts.getLanguages();
    if (_disposed) return;

    if (languages.isEmpty) {
      _setUnavailable(StoryAudioUnavailableReason.noVoices);
      return;
    }

    _languageMissing = !await _tts.isLanguageAvailable(languageCode);
    if (_disposed) return;
    _notify();
  }

  /// Play the whole story from the beginning (or resume a paused run).
  Future<void> play() async {
    if (_state == StoryPlaybackState.paused) return resume();
    await playFrom(0);
  }

  /// Play sentence [index] and keep going to the end of the story.
  Future<void> playFrom(int index) async {
    if (!_canPlay(index)) return;

    final generation = ++_generation;
    _currentIndex = index;
    _state = StoryPlaybackState.playing;
    _notify();

    await _tts.setSpeechRateMultiplier(_rate);
    if (_isStale(generation)) return;

    var i = index;
    while (i < sentences.length) {
      final speakable = sentences[i].speakable;
      if (speakable.isEmpty) {
        // Nothing to say (markup-only span). Skip it rather than reading the
        // empty string as a failed utterance and abandoning the rest.
        i++;
        if (i < sentences.length) {
          _currentIndex = i;
          _notify();
        }
        continue;
      }

      final outcome = await _tts.speakAndWait(speakable, language: languageCode);
      if (_isStale(generation)) return;

      if (outcome != TtsSpeakOutcome.completed) {
        // Cancelled, errored or unsupported: stop here rather than racing on.
        _resetToIdle();
        return;
      }

      i++;
      if (i < sentences.length) {
        _currentIndex = i;
        _notify();
      }
    }

    _resetToIdle();
  }

  /// Play a single sentence without continuing into the rest of the story.
  Future<void> playSentence(int index) async {
    if (!_canPlay(index)) return;

    final generation = ++_generation;
    _currentIndex = index;
    _state = StoryPlaybackState.playing;
    _notify();

    await _tts.setSpeechRateMultiplier(_rate);
    if (_isStale(generation)) return;

    await _tts.speakAndWait(sentences[index].speakable, language: languageCode);
    if (_isStale(generation)) return;

    _resetToIdle();
  }

  /// Pause playback, keeping the current sentence so [resume] can continue.
  ///
  /// Android emulates pause, so a refusal falls back to stopping and resuming
  /// from the start of the current sentence.
  Future<void> pause() async {
    if (_state != StoryPlaybackState.playing) return;

    final generation = ++_generation;
    _state = StoryPlaybackState.paused;
    _notify();

    final paused = await _tts.pause();
    // A pause that returns after the user has already started something else
    // must not touch it: the stop fallback below would kill that new sentence.
    if (_isStale(generation)) return;
    if (!paused) {
      await _tts.stop();
    }
  }

  /// Continue from the sentence that was playing when [pause] was called.
  Future<void> resume() async {
    if (_state != StoryPlaybackState.paused) return;
    final index = _currentIndex < 0 ? 0 : _currentIndex;
    await playFrom(index);
  }

  /// Stop playback and clear the highlight.
  Future<void> stop() async {
    _generation++;
    _resetToIdle();
    await _tts.stop();
  }

  /// Change the rate multiplier; applies to the next and to any running
  /// utterance sequence.
  Future<void> setRate(double multiplier) async {
    if (_rate == multiplier) return;
    _rate = multiplier;
    _notify();

    if (_state == StoryPlaybackState.playing) {
      // Restart the current sentence so the new rate takes effect immediately.
      final index = _currentIndex < 0 ? 0 : _currentIndex;
      await playFrom(index);
      return;
    }
    await _tts.setSpeechRateMultiplier(_rate);
  }

  bool _canPlay(int index) {
    if (!_isAvailable) return false;
    return index >= 0 && index < sentences.length;
  }

  /// True when a newer entry point (or dispose) superseded [generation].
  bool _isStale(int generation) => _disposed || generation != _generation;

  void _resetToIdle() {
    _state = StoryPlaybackState.idle;
    _currentIndex = -1;
    _notify();
  }

  void _setUnavailable(StoryAudioUnavailableReason reason) {
    _isAvailable = false;
    _unavailableReason = reason;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    // Shared singleton: stop only, never dispose.
    _tts.stop();
    super.dispose();
  }
}
