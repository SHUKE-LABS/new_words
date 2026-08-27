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

  /// The pending platform results of held `speak` calls, newest last, so a test
  /// can deliver the numeric result the plugin races against the callbacks.
  late List<Completer<dynamic>> heldSpeaks;

  /// Whether `stop` should throw, to exercise a failure before this invocation
  /// has installed its own utterance.
  bool failStop = false;

  /// Gates for `stop`/`pause`, so a test can let a new utterance start while an
  /// earlier control call is still awaiting the platform. Stops are gated
  /// individually, in call order, because the interleaving that matters is one
  /// `stop` returning *after* a later call has installed its utterance.
  bool gateStops = false;
  late List<Completer<void>> heldStops;
  Completer<void>? holdPause;

  void mockPlatform() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'speak':
          // A held `speak` never resolves, reproducing the iOS path where a
          // stopped utterance resolves nothing and only reports onCancel.
          if (holdSpeak) {
            final held = Completer<dynamic>();
            heldSpeaks.add(held);
            return held.future;
          }
          return speakResult;
        case 'stop':
          if (failStop) {
            throw PlatformException(code: 'stop_failed');
          }
          if (gateStops) {
            final gate = Completer<void>();
            heldStops.add(gate);
            await gate.future;
          }
          return 1;
        case 'getLanguages':
          return languages;
        case 'pause':
          if (holdPause != null) await holdPause!.future;
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
    heldSpeaks = [];
    failStop = false;
    gateStops = false;
    heldStops = [];
    holdPause = null;
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

    test('a stale cancel arriving after the new utterance started is dropped',
        () async {
      // The ordering the `started` flag alone could not handle: the platform
      // reports the superseded utterance's cancel only after the successor's
      // speak.onStart, so `started` is already true when it lands.
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);

      // Successor starts first...
      await emit('speak.onStart', true);
      // ...then the predecessor's owed cancel arrives. It must not end the
      // successor's sentence.
      await emit('speak.onCancel', true);

      await emit('speak.onComplete', true);
      expect(await second, TtsSpeakOutcome.completed);
    });

    test('an owed callback is consumed once, not for every later utterance',
        () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);

      await emit('speak.onStart', true);
      await emit('speak.onCancel', true); // pays the single debt
      await emit('speak.onComplete', true);
      expect(await second, TtsSpeakOutcome.completed);

      // A third utterance must see its own callbacks immediately: the debt is
      // gone, so nothing is swallowed.
      final third = service.speakAndWait('Third.');
      await pumpEventQueue();
      await emit('speak.onStart', true);
      await emit('speak.onComplete', true);
      expect(await third, TtsSpeakOutcome.completed);
    });

    test('an unpaid callback debt cannot hang the next utterance', () async {
      // If an abandoned utterance reports an error instead of the cancel it
      // owed, the debt swallows one later completion callback. The raced
      // platform result (`1` on completion, on both platforms) still settles
      // the utterance, so playback cannot stall.
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.'); // records the debt
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);
      await emit('speak.onStart', true);

      // The debt is never paid, so the completion callback is swallowed.
      await emit('speak.onComplete', true);

      // The platform result the plugin resolves alongside `onDone` still
      // arrives for this utterance, and settles it.
      heldSpeaks.last.complete(1);
      expect(
        await second.timeout(const Duration(seconds: 2),
            onTimeout: () => TtsSpeakOutcome.unsupported),
        TtsSpeakOutcome.completed,
      );
    });

    test('a failure before installing an utterance leaves a concurrent '
        'utterance pending', () async {
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      var firstSettled = false;
      unawaited(first.then((_) => firstSettled = true));

      // This invocation fails at `stop()`, before it creates its own
      // utterance, so it must not resolve the first caller's future.
      failStop = true;
      expect(await service.speakAndWait('Second.'), TtsSpeakOutcome.error);
      await pumpEventQueue();
      expect(firstSettled, isFalse,
          reason: 'a pre-assignment failure must not settle another call');

      // The first utterance still owns its callbacks.
      failStop = false;
      await emit('speak.onComplete', true);
      expect(await first, TtsSpeakOutcome.completed);
    });

    test('a stale error after the successor started aborts it, by design',
        () async {
      // Deliberate and pinned here so it cannot change silently. Android
      // reports errors by callback only — `onError` never resolves the speak
      // future (`FlutterTtsPlugin.kt` `onError`) — and an engine failure often
      // arrives before `speak.onStart`, so an error can be neither gated on
      // `started` nor allowed to pay a callback debt: either would hang the
      // sentence forever. Aborting the successor is the recoverable failure.
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);

      await emit('speak.onStart', true);
      await emit('speak.onError', 'engine failure');

      expect(await second, TtsSpeakOutcome.error);
    });

    test('a superseded call does not disable awaitSpeakCompletion for the '
        'utterance that replaced it', () async {
      // The flag is global to the plugin and gates Android's completion
      // result, so restoring it early would strip the successor's fallback.
      holdSpeak = true;
      final service = _SupportedTtsService();

      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      // The first call has now returned and run its cleanup.
      expect(await first, TtsSpeakOutcome.cancelled);
      await pumpEventQueue();

      // The engine reports the stopped utterance's cancel, as both platforms
      // do; it is owed to the predecessor and must not end the successor.
      await emit('speak.onCancel', true);

      expect(
        calls
            .where((c) => c.method == 'awaitSpeakCompletion')
            .map((c) => c.arguments)
            .toList(),
        [true, true],
        reason: 'the superseded call must leave the flag on while its '
            'successor is still speaking',
      );

      await emit('speak.onStart', true);
      await emit('speak.onComplete', true);
      expect(await second, TtsSpeakOutcome.completed);
      await pumpEventQueue();

      expect(
        calls
            .where((c) => c.method == 'awaitSpeakCompletion')
            .map((c) => c.arguments)
            .toList(),
        [true, true, false],
        reason: 'the last call out restores it exactly once',
      );
    });

    test('a completion callback that follows the platform result is not read '
        'as the successor\'s', () async {
      // iOS and web resolve the `speak` result *before* invoking
      // speak.onComplete, so the callback is still owed to the utterance that
      // just finished. If it were attributed to the next sentence, that
      // sentence would be reported finished the instant it started.
      final service = _SupportedTtsService();

      // First utterance completes via the platform result only.
      holdSpeak = true;
      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);
      heldSpeaks.last.complete(1);
      expect(await first, TtsSpeakOutcome.completed);

      // The controller immediately starts the next sentence.
      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      // Now the first utterance's completion callback finally lands.
      await emit('speak.onComplete', true);
      await pumpEventQueue();

      var secondSettled = false;
      unawaited(second.then((_) => secondSettled = true));
      await pumpEventQueue();
      expect(secondSettled, isFalse,
          reason: 'the stale completion must not end the new sentence');

      // The second utterance's own signals still resolve it.
      heldSpeaks.last.complete(1);
      expect(await second, TtsSpeakOutcome.completed);
    });

    test('a non-numeric platform result counts as completion (web)', () async {
      // The web plugin resolves its completer with no value when the utterance
      // ends; only an explicit 0 means interrupted.
      speakResult = null;
      final service = _SupportedTtsService();

      expect(await service.speakAndWait('Hello.'), TtsSpeakOutcome.completed);
    });

    test('stop does not cancel an utterance that started while it awaited '
        'the platform', () async {
      final service = _SupportedTtsService();

      holdSpeak = true;
      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      // A stop that hangs in the platform layer.
      gateStops = true;
      final stopping = service.stop();
      await pumpEventQueue();
      expect(heldStops.length, 1);

      // The user starts a new sentence. Release only *its* internal stop, so it
      // installs and starts its utterance while the earlier stop is still
      // awaiting the platform.
      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      expect(heldStops.length, 2);
      heldStops[1].complete();
      await pumpEventQueue();
      expect(await first, TtsSpeakOutcome.cancelled);
      await emit('speak.onStart', true);

      // Only now does the earlier stop return, with a different utterance in
      // flight than the one it set out to stop.
      heldStops[0].complete();
      await stopping;
      await pumpEventQueue();

      var secondSettled = false;
      unawaited(second.then((_) => secondSettled = true));
      await pumpEventQueue();
      expect(secondSettled, isFalse,
          reason: 'the earlier stop must not cancel the new utterance');

      await emit('speak.onCancel', true); // owed to the stopped utterance
      await emit('speak.onComplete', true);
      expect(await second, TtsSpeakOutcome.completed);
    });

    test('pause does not settle an utterance that started while it awaited '
        'the platform', () async {
      final service = _SupportedTtsService();

      holdSpeak = true;
      final first = service.speakAndWait('First.');
      await pumpEventQueue();
      await emit('speak.onStart', true);

      holdPause = Completer<void>();
      final pausing = service.pause();
      await pumpEventQueue();

      // Supersede the paused utterance while the pause is still in flight.
      final second = service.speakAndWait('Second.');
      await pumpEventQueue();
      holdPause!.complete();
      expect(await pausing, isTrue);
      await pumpEventQueue();

      expect(await first, TtsSpeakOutcome.cancelled);
      await emit('speak.onStart', true);

      var secondSettled = false;
      unawaited(second.then((_) => secondSettled = true));
      await pumpEventQueue();
      expect(secondSettled, isFalse,
          reason: 'the earlier pause must not settle the new utterance');
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
