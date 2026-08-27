import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:new_words/utils/app_logger_interface.dart';

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

/// Text-to-Speech service for word and sample sentence pronunciation
///
/// Supports Android, iOS, macOS, Web, Windows (not Linux)
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final AppLoggerInterface _logger;

  String? _currentLocale;
  bool _isInitialized = false;

  /// Pending completer for the in-flight [speakAndWait] utterance, if any.
  /// [speak] never sets one, so the platform handlers stay no-ops for the
  /// existing word/sentence pronunciation path.
  Completer<TtsSpeakOutcome>? _pendingSpeak;

  // Language code mapping from ISO 639-1 to TTS locales
  static const Map<String, String> _localeMap = {
    'en': 'en-US',
    'zh': 'zh-CN',
    'es': 'es-ES',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'it': 'it-IT',
    'pt': 'pt-BR',
    'ru': 'ru-RU',
    'ar': 'ar-SA',
    'hi': 'hi-IN',
    'th': 'th-TH',
    'vi': 'vi-VN',
    'id': 'id-ID',
    'ms': 'ms-MY',
    'tr': 'tr-TR',
    'pl': 'pl-PL',
    'nl': 'nl-NL',
    'sv': 'sv-SE',
    'no': 'nb-NO',
    'da': 'da-DK',
    'fi': 'fi-FI',
  };

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
      if (language != null && _currentLocale != _localeMap[language]) {
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
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    if (!isSupported) return TtsSpeakOutcome.unsupported;

    if (!_isInitialized) {
      await init(language: language);
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _logger.d('Attempted to speak empty text');
      return TtsSpeakOutcome.unsupported;
    }

    Completer<TtsSpeakOutcome>? completer;
    try {
      // Stop first, then install the completer: a cancel callback from the
      // previous utterance must not resolve this one.
      await _flutterTts.stop();
      _resolvePending(TtsSpeakOutcome.cancelled);

      if (language != null && _currentLocale != _localeMap[language]) {
        await _setLanguage(language);
      }

      completer = Completer<TtsSpeakOutcome>();
      _pendingSpeak = completer;

      await _flutterTts.awaitSpeakCompletion(true);
      try {
        await _flutterTts.speak(trimmed);
      } finally {
        await _flutterTts.awaitSpeakCompletion(false);
      }

      // With awaitSpeakCompletion the platform future already resolves at the
      // end of the utterance; the handler normally beat us here. If it did not
      // fire (platforms differ), treat the resolved future as completion — but
      // only while this call still owns the pending completer, so a newer
      // utterance is never resolved by an older one.
      if (identical(_pendingSpeak, completer)) {
        _resolvePending(TtsSpeakOutcome.completed);
      }
      return completer.future;
    } catch (e) {
      _logger.e('Failed to speak: $e');
      if (completer == null || identical(_pendingSpeak, completer)) {
        _resolvePending(TtsSpeakOutcome.error);
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

  /// Platform mapping for [setSpeechRateMultiplier]. Exposed for tests.
  @visibleForTesting
  static double speechRateForMultiplier(double multiplier) {
    // Web must be checked before Platform, which throws there.
    if (kIsWeb) return _clamp(multiplier, 0.0, 10.0);
    if (Platform.isAndroid) return _clamp(multiplier, 0.0, 2.0);
    // iOS/macOS take 0.0-1.0 with ~0.5 as normal. Windows and the remaining
    // desktop platforms are treated the same; best-effort.
    return _clamp(0.5 * multiplier, 0.0, 1.0);
  }

  static double _clamp(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);

  /// Pause playback. Best-effort: Android emulates pause and needs SDK >= 26,
  /// so `false` means the caller should fall back to stop-and-resume.
  Future<bool> pause() async {
    try {
      final result = await _flutterTts.pause();
      final paused = result == 1;
      if (paused) {
        _resolvePending(TtsSpeakOutcome.cancelled);
      }
      return paused;
    } catch (e) {
      _logger.e('Failed to pause TTS: $e');
      return false;
    }
  }

  /// The TTS locale used for an ISO 639-1 [languageCode].
  String resolveLocale(String languageCode) =>
      _localeMap[languageCode] ?? 'en-US';

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
    _flutterTts.setCompletionHandler(
      () => _resolvePending(TtsSpeakOutcome.completed),
    );
    _flutterTts.setCancelHandler(
      () => _resolvePending(TtsSpeakOutcome.cancelled),
    );
    _flutterTts.setErrorHandler((dynamic message) {
      _logger.e('TTS error: $message');
      _resolvePending(TtsSpeakOutcome.error);
    });
  }

  void _resolvePending(TtsSpeakOutcome outcome) {
    final pending = _pendingSpeak;
    if (pending == null || pending.isCompleted) return;
    _pendingSpeak = null;
    pending.complete(outcome);
  }

  /// Stop current speech
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      _logger.e('Failed to stop TTS: $e');
    } finally {
      _resolvePending(TtsSpeakOutcome.cancelled);
    }
  }

  /// Set TTS language
  Future<void> _setLanguage(String languageCode) async {
    final locale = _localeMap[languageCode] ?? 'en-US';
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
