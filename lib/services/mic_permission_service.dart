import 'package:permission_handler/permission_handler.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:new_words/utils/platform_info.dart';

/// Where microphone access stands right now, without prompting.
enum MicPermission { granted, denied, permanentlyDenied, unsupported }

/// What happened when access was actually requested.
///
/// Separate from [MicPermission] because a request can end in a state that is
/// not a permission verdict at all: the recognizer may simply be unavailable,
/// and reporting that as "denied" would send the user to a settings page that
/// cannot fix it.
enum MicRequestOutcome {
  granted,
  denied,
  permanentlyDenied,
  recognizerUnavailable,
  unsupported,
}

/// Microphone access for speaking practice, per platform.
///
/// The two platforms need different owners, and the split is deliberate:
///
/// - **Android** — `permission_handler` classifies status, requests, and
///   distinguishes a plain denial from a permanent one, which the recognizer
///   plugin cannot do.
/// - **iOS** — `SttService.initialize()` *is* the request: the recognizer
///   plugin presents both Apple prompts itself (speech recognition and the
///   microphone). `permission_handler`'s iOS strategies for microphone and
///   speech compile out unless `PERMISSION_MICROPHONE`/
///   `PERMISSION_SPEECH_RECOGNIZER` are defined in the Pods target, which this
///   app does not do, so they are never called here. `openAppSettings()` is
///   not behind those macros and works on both platforms.
class MicPermissionService {
  final SttService _stt;
  final AppLoggerInterface _logger;
  final PlatformInfo _platform;

  /// Seams for the two `permission_handler` calls, so the Android branch is
  /// testable without a device.
  final Future<PermissionStatus> Function() _readStatus;
  final Future<PermissionStatus> Function() _requestStatus;
  final Future<bool> Function() _openSettings;

  MicPermissionService({
    required SttService sttService,
    required AppLoggerInterface logger,
    PlatformInfo platform = PlatformInfo.current,
    Future<PermissionStatus> Function()? readStatus,
    Future<PermissionStatus> Function()? requestStatus,
    Future<bool> Function()? openSettings,
  }) : _stt = sttService,
       _logger = logger,
       _platform = platform,
       _readStatus = readStatus ?? (() => Permission.microphone.status),
       _requestStatus =
           requestStatus ?? (() => Permission.microphone.request()),
       _openSettings = openSettings ?? openAppSettings;

  Future<MicPermission> status() async {
    switch (classifySpeechPlatform(_platform)) {
      case SpeechPlatform.android:
        try {
          return _fromStatus(await _readStatus());
        } catch (e) {
          // Treated as not-yet-granted: the ask is still the right next step,
          // and it is the request that decides.
          _logger.e('Microphone status failed: $e');
          return MicPermission.denied;
        }
      case SpeechPlatform.ios:
        // iOS has no queryable "permanently denied" before a request: not
        // granted simply means not granted yet, and treating first use as a
        // refusal would hide the system prompt behind a settings button.
        return await _stt.hasPermission()
            ? MicPermission.granted
            : MicPermission.denied;
      case SpeechPlatform.unsupported:
        return MicPermission.unsupported;
    }
  }

  /// Asks for access, presenting the system prompt where the platform allows
  /// it, and reports what came back.
  Future<MicRequestOutcome> request() async {
    switch (classifySpeechPlatform(_platform)) {
      case SpeechPlatform.android:
        return _requestOnAndroid();
      case SpeechPlatform.ios:
        return _requestOnIOS();
      case SpeechPlatform.unsupported:
        return MicRequestOutcome.unsupported;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await _openSettings();
    } catch (e) {
      _logger.e('Opening app settings failed: $e');
      return false;
    }
  }

  Future<MicRequestOutcome> _requestOnAndroid() async {
    final PermissionStatus status;
    try {
      status = await _requestStatus();
    } catch (e) {
      _logger.e('Microphone request failed: $e');
      return MicRequestOutcome.denied;
    }

    switch (_fromStatus(status)) {
      case MicPermission.granted:
        // Granted is necessary but not sufficient: the device may still have
        // no recognizer, which initialization is the only way to find out.
        return _fromInit(await _stt.initialize());
      case MicPermission.permanentlyDenied:
        return MicRequestOutcome.permanentlyDenied;
      case MicPermission.denied:
        return MicRequestOutcome.denied;
      case MicPermission.unsupported:
        return MicRequestOutcome.unsupported;
    }
  }

  /// On iOS the request and the initialization are the same call, and a
  /// refusal is terminal: iOS presents its prompts once, so a second request
  /// would silently do nothing and Settings is the only remaining action.
  Future<MicRequestOutcome> _requestOnIOS() async {
    final result = await _stt.initialize();
    return result == SttInitResult.permissionRefused
        ? MicRequestOutcome.permanentlyDenied
        : _fromInit(result);
  }

  static MicRequestOutcome _fromInit(SttInitResult result) {
    switch (result) {
      case SttInitResult.ready:
        return MicRequestOutcome.granted;
      case SttInitResult.permissionRefused:
        return MicRequestOutcome.denied;
      case SttInitResult.recognizerUnavailable:
        return MicRequestOutcome.recognizerUnavailable;
      case SttInitResult.unsupported:
        return MicRequestOutcome.unsupported;
    }
  }

  static MicPermission _fromStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return MicPermission.granted;
    }
    // `restricted` is a parental-controls/MDM block: the user cannot grant it
    // from the prompt, so it shares the permanently-denied UI, which explains
    // the situation and offers Settings.
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicPermission.permanentlyDenied;
    }
    return MicPermission.denied;
  }
}
