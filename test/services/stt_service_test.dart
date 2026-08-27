import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/utils/platform_info.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../mocks/mock_app_logger.dart';

/// Drives `SttService` through the real `speech_to_text` method channel, so the
/// production initialization, gating and callback routing are exercised rather
/// than mocked away. Channel names, method names, argument shapes and callback
/// payloads are the locked plugin's (speech_to_text 7.4.0 over
/// speech_to_text_platform_interface 2.4.0):
///
/// - `initialize` carries `{debugLogging: ..., noBluetooth: true}` when the
///   `androidNoBluetooth` option is passed, and answers a bare bool.
/// - `locales` answers `['<localeId>:<display name>', ...]`.
/// - Recognition arrives as `textRecognition` with a JSON string; errors as
///   `notifyError` with a JSON string; status as a bare `notifyStatus` string.
///
/// The test host is Linux, so every service is built with an injected
/// `PlatformInfo` — the platform gate is behaviour under test, not scenery.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const codec = StandardMethodCodec();

  late List<MethodCall> calls;
  late MockAppLogger logger;

  /// What the platform answers `initialize` with.
  bool initResult = true;

  /// What the platform answers `has_permission` with.
  bool permissionResult = true;

  /// What the platform answers `locales` with.
  List<String> locales = ['en_US:English (United States)'];

  /// Which method, if any, should throw a PlatformException.
  String? failingMethod;

  void mockPlatform() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == failingMethod) {
            throw PlatformException(code: '${call.method}_failed');
          }
          switch (call.method) {
            case 'initialize':
              return initResult;
            case 'has_permission':
              return permissionResult;
            case 'locales':
              return locales;
            case 'listen':
              return true;
            default:
              return true;
          }
        });
  }

  /// Delivers a platform-to-Dart callback exactly as the plugin does.
  Future<void> emit(String method, dynamic arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  /// `resultType` is the plugin's own encoding: 0 partial, 2 final.
  Future<void> emitResult(String words, {required bool isFinal}) => emit(
    'textRecognition',
    jsonEncode({
      'alternates': [
        {'recognizedWords': words, 'confidence': 0.9},
      ],
      'resultType': isFinal ? 2 : 0,
    }),
  );

  Future<void> emitError(String errorMsg, {bool permanent = false}) => emit(
    'notifyError',
    jsonEncode({'errorMsg': errorMsg, 'permanent': permanent}),
  );

  /// A service on [platform] over a fresh plugin instance, so no test inherits
  /// another's initialization state.
  SttService serviceFor({PlatformInfo platform = PlatformInfo.android}) =>
      SttService(
        logger: logger,
        speech: SpeechToText.withMethodChannel(),
        platform: platform,
      );

  setUp(() {
    calls = [];
    logger = MockAppLogger();
    initResult = true;
    permissionResult = true;
    locales = ['en_US:English (United States)'];
    failingMethod = null;
    mockPlatform();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methodNames() => calls.map((c) => c.method).toList();

  MethodCall callTo(String method) =>
      calls.firstWhere((c) => c.method == method);

  /// Collects everything the service routes to the screen.
  _Recorder recorderFor(SttService service) {
    final recorder = _Recorder();
    service.attach(recorder);
    return recorder;
  }

  group('platform gate', () {
    test('Android and iOS are supported, nothing else is', () {
      expect(serviceFor(platform: PlatformInfo.android).isSupported, isTrue);
      expect(serviceFor(platform: PlatformInfo.ios).isSupported, isTrue);
      expect(serviceFor(platform: PlatformInfo.macOS).isSupported, isFalse);
      expect(serviceFor(platform: PlatformInfo.windows).isSupported, isFalse);
      expect(serviceFor(platform: PlatformInfo.linux).isSupported, isFalse);
      expect(serviceFor(platform: PlatformInfo.web).isSupported, isFalse);
    });

    test('an unsupported platform makes no channel call at all', () async {
      final service = serviceFor(platform: PlatformInfo.linux);

      expect(await service.initialize(), SttInitResult.unsupported);
      expect(await service.hasPermission(), isFalse);
      expect(await service.resolveLocaleId('en'), isNull);
      expect(await service.availableLocaleIds(), isEmpty);
      expect(await service.listen(localeId: 'en_US'), isFalse);
      await service.stop();
      await service.cancel();

      expect(calls, isEmpty);
    });
  });

  group('initialize', () {
    test('a working platform is ready and passes androidNoBluetooth', () async {
      final service = serviceFor();

      expect(await service.initialize(), SttInitResult.ready);
      expect(service.isReady, isTrue);

      final arguments = callTo('initialize').arguments as Map;
      expect(arguments['noBluetooth'], isTrue);
    });

    test('a refusal with no permission is permissionRefused', () async {
      initResult = false;
      permissionResult = false;
      final service = serviceFor();

      expect(await service.initialize(), SttInitResult.permissionRefused);
      expect(service.isReady, isFalse);
    });

    test(
      'a refusal with permission granted is recognizerUnavailable',
      () async {
        initResult = false;
        permissionResult = true;
        final service = serviceFor();

        expect(await service.initialize(), SttInitResult.recognizerUnavailable);
        expect(service.isReady, isFalse);
      },
    );

    test('a throwing platform is recognizerUnavailable, not a crash', () async {
      failingMethod = 'initialize';
      final service = serviceFor();

      expect(await service.initialize(), SttInitResult.recognizerUnavailable);
      expect(logger.errorLogs, isNotEmpty);
    });

    test(
      'success is cached: a second call makes no second channel call',
      () async {
        final service = serviceFor();
        await service.initialize();

        expect(await service.initialize(), SttInitResult.ready);
        expect(methodNames().where((m) => m == 'initialize').length, 1);
      },
    );

    test('a refusal is not cached, so granting in Settings recovers', () async {
      initResult = false;
      permissionResult = false;
      final service = serviceFor();
      expect(await service.initialize(), SttInitResult.permissionRefused);

      // The user grants the permission in Settings and comes back.
      initResult = true;
      permissionResult = true;

      expect(await service.initialize(), SttInitResult.ready);
      expect(service.isReady, isTrue);
      expect(await service.listen(localeId: 'en_US'), isTrue);
    });

    test('an unavailable recognizer is not cached either', () async {
      initResult = false;
      permissionResult = true;
      final service = serviceFor();
      expect(await service.initialize(), SttInitResult.recognizerUnavailable);

      initResult = true;

      expect(await service.initialize(), SttInitResult.ready);
    });
  });

  group('listen gating', () {
    test('refuses before a successful initialization', () async {
      final service = serviceFor();

      expect(await service.listen(localeId: 'en_US'), isFalse);
      expect(methodNames(), isNot(contains('listen')));
    });

    test('refuses after a failed initialization', () async {
      initResult = false;
      final service = serviceFor();
      await service.initialize();

      expect(await service.listen(localeId: 'en_US'), isFalse);
      expect(methodNames(), isNot(contains('listen')));
    });

    test(
      'passes the locale and the durations through SpeechListenOptions',
      () async {
        final service = serviceFor();
        await service.initialize();

        expect(await service.listen(localeId: 'en_GB'), isTrue);

        final arguments = callTo('listen').arguments as Map;
        expect(arguments['localeId'], 'en_GB');
        expect(arguments['listenFor'], SttService.listenFor.inMilliseconds);
        expect(arguments['pauseFor'], SttService.pauseFor.inMilliseconds);
        expect(arguments['partialResults'], isTrue);
      },
    );

    test('a throwing platform reports an error instead of escaping', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      failingMethod = 'listen';

      expect(await service.listen(localeId: 'en_US'), isFalse);
      expect(recorder.errors, [SttErrorKind.other]);
    });
  });

  group('locale resolution', () {
    test(
      'an unmapped language resolves to null without asking the device',
      () async {
        final service = serviceFor();
        await service.initialize();

        expect(await service.resolveLocaleId('xx'), isNull);
        expect(methodNames(), isNot(contains('locales')));
      },
    );

    test('matches the full locale regardless of separator', () async {
      locales = ['fr_FR:Français', 'en-US:English'];
      final service = serviceFor();
      await service.initialize();

      expect(await service.resolveLocaleId('en'), 'en-US');
    });

    test('falls back to the base subtag', () async {
      locales = ['en_GB:English (United Kingdom)'];
      final service = serviceFor();
      await service.initialize();

      expect(await service.resolveLocaleId('en'), 'en_GB');
    });

    test(
      'prefers the exact locale over another of the same language',
      () async {
        locales = ['en_GB:English (United Kingdom)', 'en_US:English (US)'];
        final service = serviceFor();
        await service.initialize();

        expect(await service.resolveLocaleId('en'), 'en_US');
      },
    );

    test('a language the device does not carry resolves to null', () async {
      locales = ['en_US:English (United States)'];
      final service = serviceFor();
      await service.initialize();

      expect(await service.resolveLocaleId('ja'), isNull);
    });

    test('locales are not queried before initialization succeeded', () async {
      initResult = false;
      final service = serviceFor();
      await service.initialize();

      expect(await service.resolveLocaleId('en'), isNull);
      expect(methodNames(), isNot(contains('locales')));
    });

    test(
      'a throwing platform yields no locales rather than an exception',
      () async {
        failingMethod = 'locales';
        final service = serviceFor();
        await service.initialize();

        expect(await service.availableLocaleIds(), isEmpty);
        expect(logger.errorLogs, isNotEmpty);
      },
    );
  });

  group('error mapping', () {
    test('every platform code maps to a kind', () {
      expect(
        SttService.classifyError('error_speech_timeout'),
        SttErrorKind.noSpeech,
      );
      expect(SttService.classifyError('error_no_match'), SttErrorKind.noSpeech);
      expect(
        SttService.classifyError('error_recognizer_busy'),
        SttErrorKind.busy,
      );
      expect(SttService.classifyError('error_busy'), SttErrorKind.busy);
      expect(SttService.classifyError('error_audio_error'), SttErrorKind.noMic);
      expect(SttService.classifyError('error_client'), SttErrorKind.noMic);
      expect(SttService.classifyError('error_network'), SttErrorKind.network);
      expect(
        SttService.classifyError('error_network_timeout'),
        SttErrorKind.network,
      );
      expect(
        SttService.classifyError('error_permission'),
        SttErrorKind.permission,
      );
      expect(
        SttService.classifyError('error_language_not_supported'),
        SttErrorKind.languageUnavailable,
      );
      expect(
        SttService.classifyError('error_language_unavailable'),
        SttErrorKind.languageUnavailable,
      );
      expect(SttService.classifyError('error_unknown'), SttErrorKind.other);
      expect(SttService.classifyError(''), SttErrorKind.other);
    });

    test('a platform error reaches the listener as a kind', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      await emitError('error_no_match');

      expect(recorder.errors, [SttErrorKind.noSpeech]);
    });
  });

  group('callback routing', () {
    test('partial and final results reach the listener', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      await emitResult('the morning', isFinal: false);
      await emitResult('the morning air', isFinal: true);

      expect(recorder.results, [
        ('the morning', false),
        ('the morning air', true),
      ]);
    });

    test('a silent session reaches the listener as done', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      // What the platform sends when it ends with nothing recognized.
      await emit('notifyStatus', 'doneNoResult');

      expect(recorder.doneCount, 1);
      expect(recorder.results, isEmpty);
    });

    test('notListening alone is not a done', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      await emit('notifyStatus', 'notListening');

      expect(recorder.doneCount, 0);
    });

    test(
      'attach supersedes: the previous listener hears nothing more',
      () async {
        final service = serviceFor();
        await service.initialize();
        final first = recorderFor(service);
        await service.listen(localeId: 'en_US');
        await emitResult('first session', isFinal: true);

        // A second screen opens over the same singleton.
        final second = recorderFor(service);
        await service.listen(localeId: 'en_US');
        await emitResult('second session', isFinal: true);

        expect(first.results, [('first session', true)]);
        expect(second.results, [('second session', true)]);
      },
    );

    test('detach cancels the recording and stops routing', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      service.detach(recorder);
      await emitResult('too late', isFinal: true);
      await emitError('error_no_match');

      expect(methodNames(), contains('cancel'));
      expect(recorder.results, isEmpty);
      expect(recorder.errors, isEmpty);
    });

    test(
      'a superseded listener detaching does not cancel the live session',
      () async {
        final service = serviceFor();
        await service.initialize();
        final first = recorderFor(service);
        final second = recorderFor(service);
        await service.listen(localeId: 'en_US');

        // The first screen's dispose arrives after the second attached.
        service.detach(first);

        expect(methodNames(), isNot(contains('cancel')));
        await emitResult('still mine', isFinal: true);
        expect(second.results, [('still mine', true)]);
      },
    );

    test('stop keeps the session so a final result can still arrive', () async {
      final service = serviceFor();
      await service.initialize();
      final recorder = recorderFor(service);
      await service.listen(localeId: 'en_US');

      await service.stop();
      await emitResult('said it all', isFinal: true);

      expect(methodNames(), contains('stop'));
      expect(recorder.results, [('said it all', true)]);
    });

    test('a throwing stop is logged, not propagated', () async {
      failingMethod = 'stop';
      final service = serviceFor();
      await service.initialize();
      await service.listen(localeId: 'en_US');

      await service.stop();

      expect(logger.errorLogs, isNotEmpty);
    });
  });
}

/// Records everything the service routes to its consumer.
class _Recorder implements SttListener {
  final List<(String, bool)> results = [];
  final List<SttErrorKind> errors = [];
  int doneCount = 0;

  @override
  void onSttResult(String transcript, {required bool isFinal}) {
    results.add((transcript, isFinal));
  }

  @override
  void onSttDone() {
    doneCount++;
  }

  @override
  void onSttError(SttErrorKind kind) {
    errors.add(kind);
  }
}
