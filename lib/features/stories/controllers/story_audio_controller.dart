import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:new_words/features/stories/data/story_playback_prefs.dart';
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
  final StoryPlaybackPrefs _prefs;
  final String languageCode;
  final List<SentenceSpan> sentences;

  StoryAudioController({
    required TtsService ttsService,
    required this.languageCode,
    required this.sentences,
    StoryPlaybackPrefs prefs = const StoryPlaybackPrefs(),
  }) : _tts = ttsService,
       _prefs = prefs;

  factory StoryAudioController.forContent({
    required TtsService ttsService,
    required String languageCode,
    required String content,
    StoryPlaybackPrefs prefs = const StoryPlaybackPrefs(),
  }) {
    return StoryAudioController(
      ttsService: ttsService,
      languageCode: languageCode,
      sentences: SentenceSegmenter.segment(content),
      prefs: prefs,
    );
  }

  static const List<double> rateOptions = [0.5, 0.6, 0.75, 1.0, 1.25];

  /// How many times a sentence may be spoken before playback moves on.
  static const List<int> repeatOptions = [1, 2];

  StoryPlaybackState _state = StoryPlaybackState.idle;
  int _currentIndex = -1;
  double _rate = 1.0;
  int _repeatCount = 1;
  bool _autoAdvance = false;
  bool _prepared = false;

  /// Whether the run in flight continues past its current sentence. Kept so a
  /// rate change or a resume restarts the run it belongs to, rather than
  /// turning a single sentence into a read of the rest of the story.
  bool _advancing = false;
  bool _isAvailable = true;
  StoryAudioUnavailableReason? _unavailableReason;
  bool _languageMissing = false;
  bool _disposed = false;

  /// Set the moment the learner picks a rate, so a remembered rate still in
  /// flight from [prepare] never overwrites that choice.
  bool _rateChosen = false;

  /// Invalidates in-flight utterances: every state-changing entry point bumps
  /// it, so a completion arriving from a superseded utterance is ignored. This
  /// is what keeps rapid taps from overlapping audio.
  int _generation = 0;

  StoryPlaybackState get state => _state;
  int get currentIndex => _currentIndex;
  double get rate => _rate;

  /// How many times each sentence is spoken; read afresh at every sentence
  /// boundary, so a change lands on the next sentence rather than re-cutting
  /// the one already speaking.
  int get repeatCount => _repeatCount;

  /// Whether tapping a single sentence continues into the rest of the story.
  ///
  /// Read-aloud honours this; the practice modes deliberately do not, passing
  /// `advance: false` to [playSentence] so a reference utterance never runs on
  /// into the sentence that is the next exercise's answer.
  bool get autoAdvance => _autoAdvance;

  /// True once [prepare] has settled, whatever it decided.
  bool get isPrepared => _prepared;

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
    await _restoreRate();
    if (_disposed) return;

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
    _prepared = true;
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
    await _run(index, advance: true);
  }

  /// Play sentence [index], continuing into the rest of the story only when
  /// [advance] says so.
  ///
  /// [advance] is a snapshot: it belongs to this call, so toggling
  /// [autoAdvance] while the sentence is speaking does not change what this
  /// run does.
  Future<void> playSentence(int index, {bool advance = false}) async {
    if (!_canPlay(index)) return;
    await _run(index, advance: advance);
  }

  /// The one playback loop: speaks sentence [index] [repeatCount] times and,
  /// when [advance] is set, walks on through the rest of the story.
  Future<void> _run(int index, {required bool advance}) async {
    final generation = ++_generation;
    _currentIndex = index;
    _advancing = advance;
    _state = StoryPlaybackState.playing;
    _notify();

    await _tts.setSpeechRateMultiplier(_rate);
    if (_isStale(generation)) return;

    var i = index;
    while (i < sentences.length) {
      final speakable = sentences[i].speakable;
      // Nothing to say (markup-only span): skip it rather than reading the
      // empty string as a failed utterance and abandoning the rest.
      if (speakable.isNotEmpty) {
        // Read at the sentence boundary, so a change made mid-run takes effect
        // from the next sentence and never re-cuts this one.
        final repeats = _repeatCount;
        for (var pass = 0; pass < repeats; pass++) {
          final outcome = await _tts.speakAndWait(
            speakable,
            language: languageCode,
          );
          if (_isStale(generation)) return;

          if (outcome != TtsSpeakOutcome.completed) {
            // Cancelled, errored or unsupported: stop here rather than racing
            // on.
            _resetToIdle();
            return;
          }
        }
      }

      if (!advance) break;

      i++;
      if (i < sentences.length) {
        _currentIndex = i;
        _notify();
      }
    }

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
    if (!_canPlay(index)) return;
    await _run(index, advance: _advancing);
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
    // Before the equality check: re-picking the rate already showing is still
    // a deliberate choice, and must win over a restore that has not landed.
    _rateChosen = true;
    if (_rate == multiplier) return;
    _rate = multiplier;
    _notify();
    unawaited(_prefs.saveRate(multiplier));

    if (_state == StoryPlaybackState.playing) {
      // Restart the current sentence so the new rate takes effect immediately,
      // as the run it belongs to: a single sentence must not become a read of
      // the rest of the story.
      final index = _currentIndex < 0 ? 0 : _currentIndex;
      if (!_canPlay(index)) return;
      await _run(index, advance: _advancing);
      return;
    }
    await _tts.setSpeechRateMultiplier(_rate);
  }

  /// Set how many times each sentence is spoken, clamped to [repeatOptions].
  ///
  /// A run in flight keeps the count it started the current sentence with; the
  /// new one applies from the next sentence.
  void setRepeatCount(int count) {
    final clamped = count.clamp(repeatOptions.first, repeatOptions.last);
    if (_repeatCount == clamped) return;
    _repeatCount = clamped;
    _notify();
  }

  /// Turn continue-into-the-next-sentence on or off for sentence taps.
  ///
  /// Runs already in flight keep the value they were started with.
  void setAutoAdvance(bool value) {
    if (_autoAdvance == value) return;
    _autoAdvance = value;
    _notify();
  }

  /// Apply the last rate the learner chose, if one was stored.
  ///
  /// Anything unreadable or no longer offered is dropped, leaving the default:
  /// a stale option must not become an unreachable rate the picker cannot show.
  Future<void> _restoreRate() async {
    final stored = await _prefs.loadRate();
    if (_disposed || _rateChosen) return;
    if (stored == null || !rateOptions.contains(stored)) return;
    if (_rate == stored) return;

    _rate = stored;
    _notify();
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
    // The probe has settled, unfavourably: callers waiting on [isPrepared] are
    // waiting for an answer, not for a good one.
    _prepared = true;
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
