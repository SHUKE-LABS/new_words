import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/services/mic_permission_service.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/utils/platform_info.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../mocks/mock_app_logger.dart';

/// An `SttService` whose initialization result is dictated by the test, so the
/// iOS branch — where initialization *is* the permission request — can be
/// exercised on a Linux host. Everything else is the production class.
class _FakeSttService extends SttService {
  _FakeSttService({
    required super.logger,
    required this.result,
    this.permission = false,
  }) : super(speech: SpeechToText.withMethodChannel());

  final SttInitResult result;
  final bool permission;

  int initializeCount = 0;

  @override
  Future<SttInitResult> initialize() async {
    initializeCount++;
    return result;
  }

  @override
  Future<bool> hasPermission() async => permission;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

  /// `permission_handler`'s own encodings: `Permission.microphone` is 7, and
  /// `PermissionStatus` is its index — denied 0, granted 1, restricted 2,
  /// limited 3, permanentlyDenied 4, provisional 5.
  const microphone = 7;
  const denied = 0;
  const granted = 1;
  const restricted = 2;
  const limited = 3;
  const permanentlyDenied = 4;

  late List<MethodCall> calls;
  late MockAppLogger logger;

  /// What the platform answers `checkPermissionStatus` with.
  int statusResult = granted;

  /// What the platform answers `requestPermissions` with.
  int requestResult = granted;

  bool settingsOpened = true;
  String? failingMethod;

  void mockPlatform() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == failingMethod) {
            throw PlatformException(code: '${call.method}_failed');
          }
          switch (call.method) {
            case 'checkPermissionStatus':
              return statusResult;
            case 'requestPermissions':
              return {microphone: requestResult};
            case 'openAppSettings':
              return settingsOpened;
            default:
              return null;
          }
        });
  }

  setUp(() {
    calls = [];
    logger = MockAppLogger();
    statusResult = granted;
    requestResult = granted;
    settingsOpened = true;
    failingMethod = null;
    mockPlatform();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methodNames() => calls.map((c) => c.method).toList();

  MicPermissionService serviceFor({
    required PlatformInfo platform,
    SttInitResult initResult = SttInitResult.ready,
    bool sttPermission = false,
  }) {
    return MicPermissionService(
      sttService: _FakeSttService(
        logger: logger,
        result: initResult,
        permission: sttPermission,
      ),
      logger: logger,
      platform: platform,
    );
  }

  group('Android status', () {
    test('granted', () async {
      statusResult = granted;

      expect(
        await serviceFor(platform: PlatformInfo.android).status(),
        MicPermission.granted,
      );
      expect(methodNames(), ['checkPermissionStatus']);
      expect(calls.single.arguments, microphone);
    });

    test('denied', () async {
      statusResult = denied;

      expect(
        await serviceFor(platform: PlatformInfo.android).status(),
        MicPermission.denied,
      );
    });

    test('permanently denied', () async {
      statusResult = permanentlyDenied;

      expect(
        await serviceFor(platform: PlatformInfo.android).status(),
        MicPermission.permanentlyDenied,
      );
    });

    test('restricted shares the permanently-denied path', () async {
      // Parental controls or MDM: the prompt cannot fix it, so the UI that
      // offers Settings is the honest one.
      statusResult = restricted;

      expect(
        await serviceFor(platform: PlatformInfo.android).status(),
        MicPermission.permanentlyDenied,
      );
    });

    test(
      'a throwing platform reads as not-yet-granted and is logged',
      () async {
        failingMethod = 'checkPermissionStatus';

        expect(
          await serviceFor(platform: PlatformInfo.android).status(),
          MicPermission.denied,
        );
        expect(logger.errorLogs, isNotEmpty);
      },
    );

    test('limited counts as granted', () async {
      statusResult = limited;

      expect(
        await serviceFor(platform: PlatformInfo.android).status(),
        MicPermission.granted,
      );
    });
  });

  group('Android request', () {
    test('granted plus a working recognizer is granted', () async {
      requestResult = granted;

      expect(
        await serviceFor(platform: PlatformInfo.android).request(),
        MicRequestOutcome.granted,
      );
      expect(methodNames(), ['requestPermissions']);
    });

    test(
      'granted with no recognizer is recognizerUnavailable, not denied',
      () async {
        requestResult = granted;

        expect(
          await serviceFor(
            platform: PlatformInfo.android,
            initResult: SttInitResult.recognizerUnavailable,
          ).request(),
          MicRequestOutcome.recognizerUnavailable,
        );
      },
    );

    test('denied', () async {
      requestResult = denied;

      expect(
        await serviceFor(platform: PlatformInfo.android).request(),
        MicRequestOutcome.denied,
      );
    });

    test('permanently denied', () async {
      requestResult = permanentlyDenied;

      expect(
        await serviceFor(platform: PlatformInfo.android).request(),
        MicRequestOutcome.permanentlyDenied,
      );
    });

    test('a refused permission never initializes the recognizer', () async {
      requestResult = denied;
      final stt = _FakeSttService(logger: logger, result: SttInitResult.ready);
      final service = MicPermissionService(
        sttService: stt,
        logger: logger,
        platform: PlatformInfo.android,
      );

      await service.request();

      expect(stt.initializeCount, 0);
    });

    test('a throwing platform is denied and logged, not a crash', () async {
      failingMethod = 'requestPermissions';

      expect(
        await serviceFor(platform: PlatformInfo.android).request(),
        MicRequestOutcome.denied,
      );
      expect(logger.errorLogs, isNotEmpty);
    });
  });

  group('iOS', () {
    test('status is the recognizer\'s own authorization state', () async {
      expect(
        await serviceFor(
          platform: PlatformInfo.ios,
          sttPermission: true,
        ).status(),
        MicPermission.granted,
      );
      expect(
        await serviceFor(
          platform: PlatformInfo.ios,
          sttPermission: false,
        ).status(),
        MicPermission.denied,
      );
      // Never permission_handler on iOS: its microphone and speech strategies
      // are compiled out of this app's Pods target.
      expect(calls, isEmpty);
    });

    test('first-use grant: initialization is the request', () async {
      final stt = _FakeSttService(logger: logger, result: SttInitResult.ready);
      final service = MicPermissionService(
        sttService: stt,
        logger: logger,
        platform: PlatformInfo.ios,
      );

      expect(await service.request(), MicRequestOutcome.granted);
      expect(stt.initializeCount, 1);
      expect(calls, isEmpty);
    });

    test('first-use deny is permanent: iOS never prompts twice', () async {
      expect(
        await serviceFor(
          platform: PlatformInfo.ios,
          initResult: SttInitResult.permissionRefused,
        ).request(),
        MicRequestOutcome.permanentlyDenied,
      );
    });

    test(
      'no recognizer is its own outcome, not a permission verdict',
      () async {
        expect(
          await serviceFor(
            platform: PlatformInfo.ios,
            initResult: SttInitResult.recognizerUnavailable,
          ).request(),
          MicRequestOutcome.recognizerUnavailable,
        );
      },
    );
  });

  group('unsupported platforms', () {
    test(
      'status and request answer unsupported without a channel call',
      () async {
        for (final platform in [
          PlatformInfo.macOS,
          PlatformInfo.windows,
          PlatformInfo.linux,
          PlatformInfo.web,
        ]) {
          final service = serviceFor(platform: platform);
          expect(await service.status(), MicPermission.unsupported);
          expect(await service.request(), MicRequestOutcome.unsupported);
        }
        expect(calls, isEmpty);
      },
    );
  });

  group('openSettings', () {
    test('dispatches on Android and iOS alike', () async {
      for (final platform in [PlatformInfo.android, PlatformInfo.ios]) {
        expect(await serviceFor(platform: platform).openSettings(), isTrue);
      }
      expect(methodNames(), ['openAppSettings', 'openAppSettings']);
    });

    test('a refusal from the platform is reported, not thrown', () async {
      settingsOpened = false;

      expect(
        await serviceFor(platform: PlatformInfo.android).openSettings(),
        isFalse,
      );
    });

    test('a throwing platform is false and logged', () async {
      failingMethod = 'openAppSettings';

      expect(
        await serviceFor(platform: PlatformInfo.android).openSettings(),
        isFalse,
      );
      expect(logger.errorLogs, isNotEmpty);
    });
  });
}
