import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:new_words/utils/language_locales.dart';
import 'package:new_words/utils/platform_info.dart';

/// How [SttService.initialize] finished.
enum SttInitResult {
  /// The recognizer is ready; [SttService.listen] is permitted.
  ready,

  /// The user did not grant microphone (and, on iOS, speech) access.
  permissionRefused,

  /// Access is fine but the device has no usable recognizer.
  recognizerUnavailable,

  /// Speaking practice does not run on this platform.
  unsupported,
}

/// What went wrong during recognition, mapped off the platform's raw strings.
enum SttErrorKind {
  noSpeech,
  busy,
  noMic,
  network,
  permission,
  languageUnavailable,
  other,
}

/// The one consumer of recognition events at a time.
///
/// Implemented by the screen. [SttService] holds a single slot: attaching
/// supersedes the previous listener, so a disposed screen can never be called.
abstract class SttListener {
  /// A partial or final transcript. [isFinal] marks the last one for an
  /// utterance.
  void onSttResult(String transcript, {required bool isFinal});

  /// Recognition ended without the platform delivering a final result.
  void onSttDone();

  void onSttError(SttErrorKind kind);
}

/// Speech-to-text for speaking practice, wrapping `speech_to_text`.
///
/// Every plugin call lives here — widgets talk to this service, and this
/// service owns the plugin's callbacks. The plugin's own callbacks carry no
/// consumer identity and `initialize` installs them once, so routing them
/// through a replaceable [SttListener] slot is what keeps a re-entered screen
/// from being fed a previous screen's events.
class SttService {
  final SpeechToText _speech;
  final AppLoggerInterface _logger;
  final PlatformInfo _platform;

  SttService({
    required AppLoggerInterface logger,
    SpeechToText? speech,
    PlatformInfo platform = PlatformInfo.current,
  }) : _speech = speech ?? SpeechToText(),
       _logger = logger,
       _platform = platform;

  /// How long one recording may run before the recognizer stops it.
  static const Duration listenFor = Duration(seconds: 30);

  /// How much silence ends a recording.
  static const Duration pauseFor = Duration(seconds: 3);

  SttListener? _listener;

  /// Set only once initialization succeeded; a failure is never cached, so the
  /// user can grant access in Settings and come back without restarting.
  bool _ready = false;

  SpeechPlatform get speechPlatform => classifySpeechPlatform(_platform);

  bool get isSupported => speechPlatform != SpeechPlatform.unsupported;

  bool get isListening => _speech.isListening;

  bool get isReady => _ready;

  /// Whether the user has already granted access, without prompting.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _speech.hasPermission;
    } catch (e) {
      _logger.e('STT hasPermission failed: $e');
      return false;
    }
  }

  /// Prepares the recognizer, prompting for access if the platform's own
  /// initialization does so (both Apple prompts on iOS, `RECORD_AUDIO` on
  /// Android when it has not been granted yet).
  ///
  /// Only [SttInitResult.ready] is remembered. Any other outcome leaves the
  /// service retryable, which the plugin permits: its `_initWorked` flag stays
  /// false after a failure, so its early return never blocks a second attempt.
  Future<SttInitResult> initialize() async {
    if (!isSupported) return SttInitResult.unsupported;
    if (_ready) return SttInitResult.ready;

    try {
      // The same service-owned pair every attempt: the plugin reassigns its
      // listeners on each real initialization, and a retry must not multiply
      // them or hand the plugin a consumer's callbacks.
      final worked = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        // Bluetooth headset routing is out of scope, and without this the
        // plugin asks for BLUETOOTH_CONNECT alongside RECORD_AUDIO — a
        // permission this app does not declare.
        options: [SpeechToText.androidNoBluetooth],
      );
      if (worked) {
        _ready = true;
        return SttInitResult.ready;
      }

      // The plugin reports one boolean for two very different situations, so
      // the microphone state decides which of them it was.
      final granted = await hasPermission();
      return granted
          ? SttInitResult.recognizerUnavailable
          : SttInitResult.permissionRefused;
    } catch (e) {
      _logger.e('STT initialize failed: $e');
      return SttInitResult.recognizerUnavailable;
    }
  }

  /// Routes recognition events to [listener], superseding any previous one.
  void attach(SttListener listener) {
    _listener = listener;
  }

  /// Stops routing to [listener] and cancels its recording, if it is the
  /// active one. A superseded listener detaching is a no-op.
  void detach(SttListener listener) {
    if (_listener != listener) return;
    _listener = null;
    cancel();
  }

  /// The recognizer locale id for [languageCode], or null when the language is
  /// unmapped or the device has no locale for it.
  ///
  /// Locale ids are underscore-shaped (`en_US`) on the platform side and
  /// hyphen-shaped in [LanguageLocales], so matching is separator-insensitive:
  /// the full locale first, then the base subtag, so a `en_GB`-only device
  /// still counts as supporting `en`.
  Future<String?> resolveLocaleId(String languageCode) async {
    if (!isSupported) return null;

    final mapped = LanguageLocales.localeFor(languageCode);
    if (mapped == null) return null;

    final wanted = _canonical(mapped);
    final subtag = wanted.split('_').first;

    final available = await availableLocaleIds();
    for (final id in available) {
      if (_canonical(id) == wanted) return id;
    }
    for (final id in available) {
      if (_canonical(id).split('_').first == subtag) return id;
    }
    return null;
  }

  /// The recognizer locale ids the device offers, or empty when it is not
  /// initialized — the plugin only answers this once initialization succeeded,
  /// so callers resolve a locale after [initialize] returns
  /// [SttInitResult.ready], never before.
  Future<List<String>> availableLocaleIds() async {
    if (!isSupported || !_ready) return const [];
    try {
      final locales = await _speech.locales();
      return locales.map((l) => l.localeId).toList();
    } catch (e) {
      _logger.e('STT locales failed: $e');
      return const [];
    }
  }

  /// Starts recording for [localeId].
  ///
  /// Refuses unless initialization succeeded, so the plugin's
  /// `SpeechToTextNotInitializedException` can never escape into the UI.
  Future<bool> listen({required String localeId}) async {
    if (!_ready) return false;

    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      return true;
    } catch (e) {
      _logger.e('STT listen failed: $e');
      _listener?.onSttError(SttErrorKind.other);
      return false;
    }
  }

  /// Ends the recording and keeps whatever was recognized.
  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _speech.stop();
    } catch (e) {
      _logger.e('STT stop failed: $e');
    }
  }

  /// Ends the recording and discards the result.
  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await _speech.cancel();
    } catch (e) {
      _logger.e('STT cancel failed: $e');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _listener?.onSttResult(result.recognizedWords, isFinal: result.finalResult);
  }

  void _onStatus(String status) {
    // The plugin only reports `done` once the utterance is really over: a
    // platform `done` before a final result is withheld, a silent session
    // arrives as `doneNoResult` translated to `done`, and a stop with no final
    // result promotes the last partial after the plugin's final timeout. So
    // this is the one terminal signal worth forwarding; `notListening` still
    // has a result on the way.
    if (status == SpeechToText.doneStatus) {
      _listener?.onSttDone();
    }
  }

  void _onError(SpeechRecognitionError error) {
    _logger.d('STT error: ${error.errorMsg} (permanent: ${error.permanent})');
    _listener?.onSttError(classifyError(error.errorMsg));
  }

  /// Maps the platform's raw error string onto [SttErrorKind].
  ///
  /// Pure so the mapping is testable without a device. The strings are the
  /// Android `SpeechRecognizer` codes the plugin forwards; iOS reuses them.
  static SttErrorKind classifyError(String errorMsg) {
    switch (errorMsg) {
      case 'error_speech_timeout':
      case 'error_no_match':
        return SttErrorKind.noSpeech;
      case 'error_busy':
      case 'error_recognizer_busy':
        return SttErrorKind.busy;
      case 'error_audio_error':
      case 'error_client':
        return SttErrorKind.noMic;
      case 'error_network':
      case 'error_network_timeout':
        return SttErrorKind.network;
      case 'error_permission':
        return SttErrorKind.permission;
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return SttErrorKind.languageUnavailable;
      default:
        return SttErrorKind.other;
    }
  }

  static String _canonical(String localeId) =>
      localeId.toLowerCase().replaceAll('-', '_');
}
