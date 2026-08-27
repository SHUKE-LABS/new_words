import 'dart:async';

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

/// How a [SttService.listen] ended.
enum SttStartResult {
  /// The platform confirmed it is listening.
  started,

  /// The platform refused without saying why, which is what a busy or
  /// already-listening recognizer does: it answers `false` and emits nothing.
  busy,

  /// The platform reported a failure of its own, or the call threw.
  failed,

  /// The start was cancelled before the platform confirmed it — the screen
  /// went away, or the app left the foreground.
  cancelled,
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
    Duration startTimeout = defaultStartTimeout,
  }) : _speech = speech ?? SpeechToText(),
       _logger = logger,
       _platform = platform,
       _startTimeout = startTimeout;

  /// How long one recording may run before the recognizer stops it.
  static const Duration listenFor = Duration(seconds: 30);

  /// How much silence ends a recording.
  static const Duration pauseFor = Duration(seconds: 3);

  /// How long the platform has to confirm a start before it counts as refused.
  ///
  /// A refusal is confirmed by silence, not by a return value, so this is the
  /// only bound on it. Generous: on both platforms a successful start emits the
  /// `listening` status before the channel call even returns, so this timeout
  /// is reached only when the start really did not happen.
  static const Duration defaultStartTimeout = Duration(seconds: 3);

  final Duration _startTimeout;

  SttListener? _listener;

  /// Set only once initialization succeeded; a failure is never cached, so the
  /// user can grant access in Settings and come back without restarting.
  bool _ready = false;

  /// Pending confirmation that the current [listen] actually started.
  Completer<bool>? _startSignal;

  /// Whether the platform said a start failed, rather than simply not saying
  /// anything. Distinguishes a reported failure from a silent busy refusal.
  bool _reportedFailure = false;

  /// Whether a started listen session is still running, so its events are
  /// still wanted.
  ///
  /// The plugin's callbacks carry no session identity, so this is what keeps a
  /// previous attempt's late result, error or `done` from being read as the
  /// current attempt's: events are forwarded only between a confirmed start and
  /// that session's end.
  bool _active = false;

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
  ///
  /// A new consumer owns no session yet, so any event still in flight from the
  /// previous one is dropped rather than delivered to it — including a start
  /// the previous consumer was still waiting on, whose late confirmation would
  /// otherwise open a session this one never asked for.
  void attach(SttListener listener) {
    _listener = listener;
    _active = false;
    _abandonPendingStart();
  }

  /// Gives up on a start that has not been confirmed yet, so a `listening`
  /// status arriving after it can no longer open a session.
  void _abandonPendingStart() {
    final signal = _startSignal;
    _startSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete(false);
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

  /// Starts recording for [localeId], reporting whether the platform really
  /// began listening.
  ///
  /// Refuses unless initialization succeeded, so the plugin's
  /// `SpeechToTextNotInitializedException` can never escape into the UI.
  ///
  /// The plugin's own `listen` returns nothing: it swallows the platform's
  /// started flag, so a recognizer that refuses to start — busy, already
  /// listening, an SDK too low — completes the call normally and then delivers
  /// no callbacks and no timer at all. Waiting for the platform's `listening`
  /// status is therefore the only honest start signal. It arrives before the
  /// channel call returns on a real start, so this waits only when the start
  /// failed.
  ///
  /// The distinction the caller needs is between a refusal the platform
  /// explained and one it did not: silence is Android's busy answer, so it maps
  /// to [SttStartResult.busy], while a reported failure resolves the wait
  /// instead of timing out and maps to [SttStartResult.failed].
  Future<SttStartResult> listen({required String localeId}) async {
    if (!_ready) return SttStartResult.failed;
    // A second start while the first is still unconfirmed would take over the
    // signal and leave the first to time out — and its timeout cleanup would
    // then cancel the session that did start.
    if (_startSignal != null) {
      _logger.e('STT listen called while a start was still pending');
      return SttStartResult.cancelled;
    }

    // Armed before the call: on both platforms the status is emitted from
    // inside the native start, so it can already be here when it returns.
    final signal = Completer<bool>();
    _startSignal = signal;
    _reportedFailure = false;

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
    } catch (e) {
      if (_startSignal == signal) _startSignal = null;
      _active = false;
      _logger.e('STT listen failed: $e');
      // The return value carries the failure; an error event on top of it would
      // report the same thing twice, and racing to be the message the screen
      // shows.
      return SttStartResult.failed;
    }

    // A pending signal means nothing has answered yet; anything that resolves
    // it — the status, a cancel, a new listener, the timeout — decides how.
    final confirmed = await signal.future.timeout(
      _startTimeout,
      onTimeout: () => false,
    );
    final wasCurrent = _startSignal == signal;
    if (wasCurrent) _startSignal = null;

    if (confirmed) return SttStartResult.started;

    if (!wasCurrent) {
      // Something else invalidated this start — a cancel, or another screen
      // attaching — so it is not a platform refusal and has already been
      // cleaned up.
      return SttStartResult.cancelled;
    }

    _logger.e('STT listen was not confirmed by the platform');
    // The native side may hold a half-open recognizer, and the next attempt
    // would be refused for being busy.
    await cancel();
    // Silence is the Android refusal: `startListening` answers false and emits
    // no status when the recognizer is busy or already listening. A platform
    // that reports its own failure resolves the signal instead of timing out,
    // and lands in [SttStartResult.failed] through [_onStatus].
    return _reportedFailure ? SttStartResult.failed : SttStartResult.busy;
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

  /// Ends the recording and discards the result, along with anything the
  /// session still has in flight.
  Future<void> cancel() async {
    _active = false;
    _abandonPendingStart();
    if (!isSupported) return;
    try {
      await _speech.cancel();
    } catch (e) {
      _logger.e('STT cancel failed: $e');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_active) return;
    _listener?.onSttResult(result.recognizedWords, isFinal: result.finalResult);
  }

  void _onStatus(String status) {
    final signal = _startSignal;
    if (signal != null && !signal.isCompleted) {
      // Still waiting on a start: `listening` is the confirmation, and any
      // other terminal status means the start did not take.
      if (status == SpeechToText.listeningStatus) {
        _active = true;
        signal.complete(true);
      } else if (status == SpeechToText.notListeningStatus ||
          status == SpeechToText.doneStatus) {
        _reportedFailure = true;
        signal.complete(false);
      }
      return;
    }

    // The plugin only reports `done` once the utterance is really over: a
    // platform `done` before a final result is withheld, a silent session
    // arrives as `doneNoResult` translated to `done`, and a stop with no final
    // result promotes the last partial after the plugin's final timeout. So
    // this is the one terminal signal worth forwarding; `notListening` still
    // has a result on the way.
    if (status == SpeechToText.doneStatus) {
      if (!_active) return;
      _active = false;
      _listener?.onSttDone();
    }
  }

  void _onError(SpeechRecognitionError error) {
    _logger.d('STT error: ${error.errorMsg} (permanent: ${error.permanent})');
    // An error belonging to no live session is stale — a failed start reports
    // itself through [listen]'s return value instead.
    if (!_active) return;
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
