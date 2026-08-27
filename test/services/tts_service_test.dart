import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/services/tts_service.dart';

/// Drives `TtsService` through the real `flutter_tts` method channel, so the
/// production completion/cancel/error handling is exercised rather than mocked
/// away. Platform results and callbacks mirror the locked plugin
/// (flutter_tts 4.2.5):
///
/// - Android resolves `speak` with `1` on completion and `0` when stop/pause
///   interrupts it or the engine rejects the utterance while already speaking.
/// - iOS resolves a stopped `speak` with nothing at all and only reports
///   `speak.onCancel`.
/// - Neither platform resolves `speak` on error; both report `speak.onError`.
/// - No callback carries an utterance id.
/// The test host is Linux, where `isSupported` is genuinely false, so the
/// platform gate is overridden to exercise everything behind it. Every other
/// method — including all channel traffic — is the production implementation.
class _SupportedTtsService extends TtsService {
  @override
  bool get isSupported => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();

  late List<MethodCall> calls;

  /// Result for `speak` when it resolves immediately.
  dynamic speakResult = 1;
  dynamic pauseResult = 1;
  List<String> languages = ['en-US', 'en-GB', 'zh-CN'];

  /// Whether `speak` should hang until the test resolves it.
  bool holdSpeak = false;

  void mockPlatform() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'speak':
          // A held `speak` never resolves, reproducing the iOS path where a
          // stopped utterance resolves nothing and only reports onCancel.
          if (holdSpeak) return Completer<dynamic>().future;
          return speakResult;
        case 'getLanguages':
          return languages;
        case 'pause':
          return pauseResult;
        default:
          return 1;
      }
    });
  }

  /// Delivers a platform-to-Dart callback exactly as the plugin does.
  Future<void> emit(String method, [dynamic arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  setUp(() {
    calls = [];
    speakResult = 1;
    pauseResult = 1;
    holdSpeak = false;
    languages = ['en-US', 'en-GB', 'zh-CN'];
    mockPlatform();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methodNames() => calls.map((c) => c.method).toList();

  group('speakAndWait outcomes', () {
    test('completed when the platform resolves speak with 1', () async {
      final service = _SupportedTtsService();

      expect(
        await service.speakAndWait('Hello.', language: 'en'),
        TtsSpeakOutcome.completed,
      );
    });

    test('cancelled when the platform resolves speak with 0 (Android stop)',
        () async {
      speakResult = 0;
      final service = _SupportedTtsService();

      expect(
        await service.speakAndWait('Hello.'),
        TtsSpeakOutcome.cancelled,
      );
    });

    test('cancelled on speak.onCancel when speak never resolves (iOS stop)',
        () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final outcome = service.speakAndWait('Hello.');
      await pumpEventQueue();

      await emit('speak.onStart', true);
      await emit('speak.onCancel', true);

      expect(await outcome, TtsSpeakOutcome.cancelled);
    });

    test('error on speak.onError, which never resolves speak', () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final outcome = service.speakAndWait('Hello.');
      await pumpEventQueue();

      await emit('speak.onStart', true);
      await emit('speak.onError', 'boom');

      expect(await outcome, TtsSpeakOutcome.error);
    });

    test('unsupported for empty text, without touching the platform', () async {
      final service = _SupportedTtsService();

      expect(await service.speakAndWait('   '), TtsSpeakOutcome.unsupported);
      expect(methodNames(), isNot(contains('speak')));
    });

    test('returns error instead of throwing when initialization fails',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'setSharedInstance') {
          throw PlatformException(code: 'no-engine');
        }
        return 1;
      });
      final service = _SupportedTtsService();

      expect(await service.speakAndWait('Hello.'), TtsSpeakOutcome.error);
    });

    test('enables awaitSpeakCompletion only for the duration of the call',
        () async {
      final service = _SupportedTtsService();
      await service.speakAndWait('Hello.');

      final awaits = calls
          .where((c) => c.method == 'awaitSpeakCompletion')
          .map((c) => c.arguments)
          .toList();
      expect(awaits, [true, false]);
    });
  });

  group('stale callbacks', () {
    test('a late cancel from the previous utterance does not cancel the new one',
        () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      // First utterance starts and is speaking.
      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      // A second utterance supersedes it: stop() is issued, and the first
      // resolves as cancelled.
      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);

      // The previous utterance's cancel callback arrives late, after the new
      // completer is installed and before the new utterance starts. It must be
      // dropped rather than resolve the new utterance.
      await emit('speak.onCancel', true);

      // The new utterance then runs to completion normally.
      await emit('speak.onStart', true);
      await emit('speak.onComplete', true);

      expect(await second, TtsSpeakOutcome.completed);
    });

    test('a late completion from the previous utterance is dropped too',
        () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);

      await emit('speak.onComplete', true);
      await emit('speak.onStart', true);
      await emit('speak.onCancel', true);

      expect(await second, TtsSpeakOutcome.cancelled);
    });

    test('stop resolves a pending utterance as cancelled', () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final outcome = service.speakAndWait('Hello.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      await service.stop();
      expect(await outcome, TtsSpeakOutcome.cancelled);
    });

    test('a successful pause resolves the pending utterance as cancelled',
        () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final outcome = service.speakAndWait('Hello.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      expect(await service.pause(), isTrue);
      expect(await outcome, TtsSpeakOutcome.cancelled);
    });

    test('a refused pause reports false and leaves playback pending', () async {
      holdSpeak = true;
      pauseResult = 0;
      final service = _SupportedTtsService();

      final outcome = service.speakAndWait('Hello.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      expect(await service.pause(), isFalse);

      // The caller falls back to stop(), which settles the utterance.
      await service.stop();
      expect(await outcome, TtsSpeakOutcome.cancelled);
    });
  });

  group('speak (word detail path) is unchanged', () {
    test('stops then speaks, and never awaits completion', () async {
      final service = _SupportedTtsService();
      await service.speak('Hello', language: 'en');

      expect(methodNames(), contains('speak'));
      expect(
        calls.where((c) => c.method == 'awaitSpeakCompletion'),
        isEmpty,
        reason: 'the fire-and-forget path must not toggle completion awaiting',
      );
      expect(
        methodNames().indexOf('stop'),
        lessThan(methodNames().indexOf('speak')),
      );
    });

    test('a completion callback with no pending utterance is harmless',
        () async {
      final service = _SupportedTtsService();
      await service.speak('Hello', language: 'en');

      await emit('speak.onStart', true);
      await emit('speak.onComplete', true);
      await emit('speak.onCancel', true);
      // Reaching here without an exception is the assertion.
      expect(methodNames(), contains('speak'));
    });
  });

  group('platform support gate', () {
    test('a real unsupported host refuses to speak without any channel call',
        () async {
      final service = TtsService(); // Linux host: isSupported is false.

      expect(service.isSupported, isFalse);
      expect(await service.speakAndWait('Hello.'), TtsSpeakOutcome.unsupported);
      expect(methodNames(), isEmpty);
    });
  });

  group('speech rate mapping', () {
    test('web takes the multiplier directly, clamped to 0-10', () {
      expect(TtsService.rateFor(1.0, isWeb: true, isAndroid: false), 1.0);
      expect(TtsService.rateFor(1.25, isWeb: true, isAndroid: false), 1.25);
      expect(TtsService.rateFor(20.0, isWeb: true, isAndroid: false), 10.0);
      expect(TtsService.rateFor(-1.0, isWeb: true, isAndroid: false), 0.0);
    });

    test('android normal is 1.0, clamped to 0-2', () {
      expect(TtsService.rateFor(1.0, isWeb: false, isAndroid: true), 1.0);
      expect(TtsService.rateFor(0.75, isWeb: false, isAndroid: true), 0.75);
      expect(TtsService.rateFor(1.25, isWeb: false, isAndroid: true), 1.25);
      expect(TtsService.rateFor(3.0, isWeb: false, isAndroid: true), 2.0);
    });

    test('apple and desktop normal is 0.5, clamped to 0-1', () {
      expect(TtsService.rateFor(1.0, isWeb: false, isAndroid: false), 0.5);
      expect(TtsService.rateFor(0.75, isWeb: false, isAndroid: false), 0.375);
      expect(TtsService.rateFor(1.25, isWeb: false, isAndroid: false), 0.625);
      expect(TtsService.rateFor(4.0, isWeb: false, isAndroid: false), 1.0);
    });

    test('never passes the raw multiplier through on apple platforms', () {
      for (final multiplier in [0.75, 1.0, 1.25]) {
        expect(
          TtsService.rateFor(multiplier, isWeb: false, isAndroid: false),
          isNot(multiplier),
        );
      }
    });

    test('setSpeechRateMultiplier forwards the mapped value', () async {
      final service = _SupportedTtsService();
      await service.setSpeechRateMultiplier(1.25);

      final call = calls.firstWhere((c) => c.method == 'setSpeechRate');
      expect(call.arguments, TtsService.speechRateForMultiplier(1.25));
    });
  });

  group('locale handling', () {
    test('resolveLocale maps known codes and falls back to en-US', () {
      final service = _SupportedTtsService();
      expect(service.resolveLocale('zh'), 'zh-CN');
      expect(service.resolveLocale('en'), 'en-US');
      expect(service.resolveLocale('xx'), 'en-US');
    });

    test('matches an exactly installed locale', () async {
      final service = _SupportedTtsService();
      expect(await service.isLanguageAvailable('zh'), isTrue);
    });

    test('matches on the language subtag when the region differs', () async {
      languages = ['en-GB'];
      final service = _SupportedTtsService();
      expect(await service.isLanguageAvailable('en'), isTrue);
    });

    test('false when the language is not installed', () async {
      languages = ['fr-FR'];
      final service = _SupportedTtsService();
      expect(await service.isLanguageAvailable('zh'), isFalse);
    });

    test('false when the device reports no languages', () async {
      languages = [];
      final service = _SupportedTtsService();
      expect(await service.isLanguageAvailable('en'), isFalse);
    });

    test('getLanguages converts a dynamic platform list element-wise',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getLanguages') {
          // The platform hands back a List<dynamic>, not a List<String>.
          return <dynamic>['en-US', 'zh-CN'];
        }
        return 1;
      });
      final service = _SupportedTtsService();

      expect(await service.getLanguages(), ['en-US', 'zh-CN']);
    });
  });
}
