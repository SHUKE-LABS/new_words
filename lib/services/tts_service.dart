import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:new_words/utils/language_locales.dart';

/// How a [TtsService.speakAndWait] utterance finished.
enum TtsSpeakOutcome {
  /// The whole utterance was spoken.
  completed,

  /// Interrupted by stop/pause or by a newer utterance.
  cancelled,

  /// The platform reported an error.
  error,

  /// TTS is not available on this platform, or the text was empty.
  unsupported,
}

/// One in-flight [TtsService.speakAndWait] utterance.
///
/// `flutter_tts` callbacks carry no utterance id, so ownership is tracked here:
/// [started] records that this utterance's own playback began, and
/// [terminalCallbackSeen] that the platform has already reported its end. See
/// [TtsService._handleTerminalCallback] for how the two combine.
class _Utterance {
  final Completer<TtsSpeakOutcome> completer = Completer<TtsSpeakOutcome>();
  bool started = false;
  bool terminalCallbackSeen = false;
}

/// Text-to-Speech service for word and sample sentence pronunciation
///
/// Supports Android, iOS, macOS, Web, Windows (not Linux)
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final AppLoggerInterface _logger;

  String? _currentLocale;
  bool _isInitialized = false;

  /// The in-flight [speakAndWait] utterance, if any. [speak] never sets one,
  /// so the platform handlers stay no-ops for the existing word/sentence
  /// pronunciation path.
  _Utterance? _current;

  /// Terminal callbacks the platform still owes utterances we abandoned.
  ///
  /// Stopping a started utterance makes the engine report its end
  /// (`speak.onCancel`, or `speak.onComplete` when it finished in the same
  /// instant), and those callbacks carry no utterance id. Each abandonment
  /// therefore records a debt that the next completion/cancel pays off instead
  /// of being attributed to the successor — which is what makes ownership
  /// correct whether the stale callback arrives before or after the successor's
  /// `speak.onStart`.
  int _owedTerminalCallbacks = 0;

  /// How many [speakAndWait] calls are still inside their utterance.
  ///
  /// `awaitSpeakCompletion` is global to the plugin, so a superseded call must
  /// not restore it while its successor is still speaking: on Android the
  /// completion result is only delivered when it is enabled
  /// (`FlutterTtsPlugin.kt` `onDone`), so an early restore would strip the
  /// successor's fallback signal. Only the last call out turns it off.
  int _awaitCompletionHolders = 0;

  TtsService({AppLoggerInterface? logger})
      : _logger = logger ?? const _DefaultLogger();

  /// Initialize TTS with optional language
  Future<void> init({String? language}) async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setSharedInstance(true);
      _installHandlers();
      await _setLanguage(language ?? 'en');
      _isInitialized = true;
      _logger.i('TTS initialized with language: $_currentLocale');
    } catch (e) {
      _logger.e('Failed to initialize TTS: $e');
      rethrow;
    }
  }

  /// Speak text with specified language
  Future<void> speak(String text, {String? language}) async {
    if (!_isInitialized) {
      await init(language: language);
    }

    if (text.isEmpty) {
      _logger.d('Attempted to speak empty text');
      return;
    }

    try {
      // Stop any ongoing speech
      await _flutterTts.stop();

      // Set language if different from current
      if (language != null && _currentLocale != resolveLocale(language)) {
        await _setLanguage(language);
      }

      await _flutterTts.speak(text);
      _logger.i('Speaking: "${text.length > 50 ? text.substring(0, 50) : text}"');
    } catch (e) {
      _logger.e('Failed to speak: $e');
    }
  }

  /// Speak [text] and wait until it finishes, is cancelled, or errors.
  ///
  /// Additive counterpart to [speak], which stays fire-and-forget. Sequential
  /// playback (story read-aloud) needs a future that resolves at the end of the
  /// utterance, so `awaitSpeakCompletion` is enabled for the duration of this
  /// call only and restored afterwards.
  ///
  /// The outcome comes from whichever signal arrives first, because the
  /// platforms differ: on Android `speak` resolves with `1` on completion and
  /// `0` when stop/pause interrupts it or the engine rejects the utterance,
  /// while on iOS a stopped utterance resolves nothing at all and only reports
  /// `speak.onCancel`. Errors are reported by callback on both.
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    if (!isSupported) return TtsSpeakOutcome.unsupported;

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _logger.d('Attempted to speak empty text');
      return TtsSpeakOutcome.unsupported;
    }

    _Utterance? utterance;
    var holdsAwaitCompletion = false;
    try {
      if (!_isInitialized) {
        // Initialization failures must surface as an outcome, not as an
        // exception thrown through the caller's playback loop.
        await init(language: language);
      }

      await _flutterTts.stop();

      if (language != null && _currentLocale != resolveLocale(language)) {
        await _setLanguage(language);
      }

      // Settle whatever is in flight immediately before installing this
      // utterance, never earlier: the language step above can await, and a
      // concurrent caller that installed during it would otherwise be orphaned
      // by the assignment below and hang. At this instant anything current is
      // genuinely superseded — the engine was stopped above.
      _supersedeCurrent();

      utterance = _Utterance();
      final pending = utterance;
      _current = pending;

      _awaitCompletionHolders++;
      holdsAwaitCompletion = true;
      await _flutterTts.awaitSpeakCompletion(true);

      // Deliberately not awaited: on iOS a stopped utterance never resolves
      // `speak` at all, so awaiting it here would hang even though
      // `speak.onCancel` already reported the outcome. Whichever signal
      // arrives first settles the utterance; `_settle` clears `_current`, so
      // the loser is dropped.
      unawaited(
        _flutterTts.speak(trimmed).then(
          (dynamic result) {
            if (!identical(_current, pending)) return;
            // Only an explicit `0` means interrupted: Android resolves `0` when
            // stop/pause cuts the utterance short or the engine rejects it
            // under QUEUE_FLUSH, iOS resolves `1` on completion and nothing at
            // all on stop, and the web plugin resolves its completer with *no
            // value* when the utterance ends. Treating anything non-zero as
            // completion is what keeps sequential playback moving on web.
            final interrupted = result == 0;
            // iOS and web both resolve this future *before* invoking
            // `speak.onComplete` (`SwiftFlutterTtsPlugin.swift` `didFinish`,
            // `flutter_tts_web.dart` `onEnd`), so that callback is still owed
            // to this utterance and must not be read as the successor's.
            _oweTerminalCallback(pending);
            _settle(
              interrupted
                  ? TtsSpeakOutcome.cancelled
                  : TtsSpeakOutcome.completed,
            );
          },
          onError: (Object e) {
            _logger.e('Failed to speak: $e');
            if (identical(_current, pending)) {
              _settle(TtsSpeakOutcome.error);
            }
          },
        ),
      );

      final outcome = await pending.completer.future;
      await _releaseAwaitCompletion();
      return outcome;
    } catch (e) {
      _logger.e('Failed to speak: $e');
      // Only settle what this invocation owns. Failing before installing our
      // own utterance (init, stop or setLanguage threw) must not resolve a
      // concurrent caller's pending future.
      if (utterance != null && identical(_current, utterance)) {
        _settle(TtsSpeakOutcome.error);
      }
      if (holdsAwaitCompletion) {
        await _releaseAwaitCompletion();
      }
      return TtsSpeakOutcome.error;
    }
  }

  /// Set the speech rate from a UI multiplier (e.g. 0.75, 1.0, 1.25).
  ///
  /// `flutter_tts` rate ranges differ per platform, so the multiplier is mapped
  /// rather than passed through: normal speed is 1.0 on Android and Web, 0.5 on
  /// Apple platforms.
  Future<void> setSpeechRateMultiplier(double multiplier) async {
    final rate = speechRateForMultiplier(multiplier);
    try {
      await _flutterTts.setSpeechRate(rate);
    } catch (e) {
      _logger.e('Failed to set speech rate: $e');
    }
  }

  /// Platform mapping for [setSpeechRateMultiplier].
  static double speechRateForMultiplier(double multiplier) {
    // Web must be checked before Platform, which throws there.
    final isWeb = kIsWeb;
    return rateFor(
      multiplier,
      isWeb: isWeb,
      isAndroid: !isWeb && Platform.isAndroid,
    );
  }

  /// Pure platform mapping, so each branch is testable off-device.
  @visibleForTesting
  static double rateFor(
    double multiplier, {
    required bool isWeb,
    required bool isAndroid,
  }) {
    if (isWeb) return _clamp(multiplier, 0.0, 10.0);
    if (isAndroid) return _clamp(multiplier, 0.0, 2.0);
    // iOS/macOS take 0.0-1.0 with ~0.5 as normal. Windows and the remaining
    // desktop platforms are treated the same; best-effort.
    return _clamp(0.5 * multiplier, 0.0, 1.0);
  }

  static double _clamp(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);

  /// Pause playback. Best-effort: Android emulates pause and needs SDK >= 26,
  /// so `false` means the caller should fall back to stop-and-resume.
  Future<bool> pause() async {
    // Captured up front for the same reason as [stop].
    final owner = _current;
    try {
      final result = await _flutterTts.pause();
      final paused = result == 1;
      // Only the utterance this call set out to pause, and only if it is still
      // the one in flight: nothing in flight at entry means there is nothing of
      // ours to settle. A pause reports `speak.onPause` on both platforms
      // rather than a cancel, so no callback is owed here.
      if (paused && owner != null && identical(_current, owner)) {
        _settle(TtsSpeakOutcome.cancelled);
      }
      return paused;
    } catch (e) {
      _logger.e('Failed to pause TTS: $e');
      return false;
    }
  }

  /// The TTS locale used for an ISO 639-1 [languageCode].
  ///
  /// An unmapped code falls back to `en-US`, which is this service's
  /// long-standing behaviour: speaking a word in the wrong voice is better than
  /// not speaking it. [LanguageLocales.localeFor] itself is fallback-free, so
  /// recognition — where the wrong language is worse than none — can refuse an
  /// unknown code instead.
  String resolveLocale(String languageCode) =>
      LanguageLocales.localeFor(languageCode) ?? 'en-US';

  /// Whether a voice for [languageCode] is installed on this device.
  ///
  /// Matches the full locale first, then the bare language subtag, so
  /// `en-GB`-only devices still count as supporting `en`.
  Future<bool> isLanguageAvailable(String languageCode) async {
    final locale = resolveLocale(languageCode).toLowerCase();
    final subtag = locale.split('-').first;

    final available =
        (await getLanguages()).map((l) => l.toLowerCase()).toList();
    if (available.isEmpty) return false;

    return available.any((l) => l == locale || l.split('-').first == subtag);
  }

  void _installHandlers() {
    _flutterTts.setStartHandler(() => _current?.started = true);
    _flutterTts.setCompletionHandler(
      () => _handleTerminalCallback(TtsSpeakOutcome.completed),
    );
    _flutterTts.setCancelHandler(
      () => _handleTerminalCallback(TtsSpeakOutcome.cancelled),
    );
    _flutterTts.setErrorHandler((dynamic message) {
      _logger.e('TTS error: $message');
      // Errors are terminal and Android reports them by callback only — its
      // `onError` never resolves the speak future — so an error is never
      // treated as an owed callback and is never gated on `started`. Doing
      // either could hang playback permanently; a stale error aborting its
      // successor is the strictly safer failure.
      _settle(TtsSpeakOutcome.error);
    });
  }

  /// Gives up this call's claim on the global `awaitSpeakCompletion` flag,
  /// turning it off only once no other call is still speaking.
  Future<void> _releaseAwaitCompletion() async {
    if (_awaitCompletionHolders > 0) _awaitCompletionHolders--;
    if (_awaitCompletionHolders > 0) return;
    try {
      await _flutterTts.awaitSpeakCompletion(false);
    } catch (e) {
      _logger.e('Failed to restore awaitSpeakCompletion: $e');
    }
  }

  /// Attributes a completion/cancel callback to the utterance that owns it.
  ///
  /// The callbacks carry no utterance id, so ownership is decided in two steps:
  ///
  /// 1. An outstanding debt is paid first. A callback owed by an utterance we
  ///    abandoned is dropped no matter when it lands, which is what the
  ///    `started` flag alone could not do — a predecessor's callback arriving
  ///    *after* the successor's `speak.onStart` used to end the wrong sentence.
  /// 2. Otherwise it must belong to an utterance whose own playback has begun.
  ///
  /// A debt can be left unpaid if the abandoned utterance ends up reporting an
  /// error instead, in which case it swallows one later completion. That cannot
  /// hang playback: both platforms resolve the `speak` future with `1` on
  /// completion as well (`FlutterTtsPlugin.kt` `onDone`,
  /// `SwiftFlutterTtsPlugin.swift` `didFinish`), and that raced future settles
  /// the utterance independently.
  void _handleTerminalCallback(TtsSpeakOutcome outcome) {
    if (_owedTerminalCallbacks > 0) {
      _owedTerminalCallbacks--;
      return;
    }

    final utterance = _current;
    if (utterance == null || !utterance.started) return;
    utterance.terminalCallbackSeen = true;
    _settle(outcome);
  }

  /// Cancels whatever is in flight, used at install time in [speakAndWait]:
  /// the engine has just been stopped, so anything still current is genuinely
  /// superseded. Deliberately a wildcard — it must never be reached from a
  /// control call that awaited the platform first, or it would cancel a
  /// sentence that call never targeted.
  void _supersedeCurrent() {
    final utterance = _current;
    if (utterance == null) return;
    _oweTerminalCallback(utterance);
    _settle(TtsSpeakOutcome.cancelled);
  }

  /// Cleanup for [stop]: acts only on the utterance the call set out to stop.
  ///
  /// A null [owner] means nothing was in flight when the call started, so it
  /// has nothing of its own to settle and this is a no-op. Treating null as
  /// "whatever is current now" would cancel an utterance installed during the
  /// platform round trip.
  void _abandonOwned(_Utterance? owner) {
    if (owner == null || !identical(_current, owner)) return;
    _oweTerminalCallback(owner);
    _settle(TtsSpeakOutcome.cancelled);
  }

  /// Records that the platform still owes [utterance] a terminal callback.
  ///
  /// Uncapped: there is no bound on how many settled utterances can be waiting
  /// on a delayed callback, so capping this would let the surplus callbacks
  /// through to be attributed to a later utterance. The counter is simply how
  /// many terminal callbacks are owed to utterances that have already finished.
  ///
  /// The residual limitation is the opposite one: a platform that promises a
  /// terminal callback and never sends it leaves a debt that swallows one later
  /// callback. That cannot hang playback — both platforms also resolve the
  /// `speak` future on completion, and that raced result settles the utterance
  /// independently (asserted by test).
  void _oweTerminalCallback(_Utterance utterance) {
    if (!utterance.started ||
        utterance.terminalCallbackSeen ||
        utterance.completer.isCompleted) {
      return;
    }
    _owedTerminalCallbacks++;
  }

  void _settle(TtsSpeakOutcome outcome) {
    final utterance = _current;
    if (utterance == null || utterance.completer.isCompleted) return;
    _current = null;
    utterance.completer.complete(outcome);
  }

  /// Stop current speech
  ///
  /// The utterance this call is stopping is captured up front: awaiting the
  /// platform call gives a concurrent `speakAndWait` time to install a new
  /// utterance, and cancelling *that* one would kill the sentence the user just
  /// started.
  Future<void> stop() async {
    final owner = _current;
    try {
      await _flutterTts.stop();
    } catch (e) {
      _logger.e('Failed to stop TTS: $e');
    } finally {
      _abandonOwned(owner);
    }
  }

  /// Set TTS language
  Future<void> _setLanguage(String languageCode) async {
    final locale = resolveLocale(languageCode);
    await _flutterTts.setLanguage(locale);
    _currentLocale = locale;
  }

  bool get isSupported {
    try {
      return !Platform.isLinux;
    } on UnsupportedError {
      // Web: dart:io's Platform throws rather than reporting a platform.
      return false;
    }
  }

  /// Get available languages for TTS
  Future<List<String>> getLanguages() async {
    try {
      // The platform channel yields a List<dynamic>; convert element-wise
      // rather than relying on a list cast, which throws on Android.
      final dynamic languages = await _flutterTts.getLanguages;
      if (languages is! Iterable) return [];
      return languages.map((dynamic l) => l.toString()).toList();
    } catch (e) {
      _logger.e('Failed to get languages: $e');
      return [];
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}

/// Default logger for when no logger is injected
class _DefaultLogger implements AppLoggerInterface {
  const _DefaultLogger();

  @override
  void i(String message) {
    // Silent in production
  }

  @override
  void d(String message) {
    // Silent in production
  }

  @override
  void e(String message) {
    // Silent in production
  }

  @override
  Future<void> initialize() async {
    // No-op for default logger
  }
}
