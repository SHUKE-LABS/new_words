import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/presentation/speaking_view.dart';
import 'package:new_words/features/practice/utils/listening_set_builder.dart';
import 'package:new_words/features/stories/controllers/story_audio_controller.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/services/mic_permission_service.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/utils/platform_info.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/mock_app_logger.dart';

/// A TTS service that never touches a platform channel: what the view asked to
/// speak, and how often, is what the assertions read.
class _FakeTtsService extends TtsService {
  _FakeTtsService({this.languageAvailable = true, List<String>? ordering})
    : ordering = ordering ?? [];

  final bool languageAvailable;

  /// Shared with the STT fake, so a test can prove the microphone was closed
  /// *before* the reference started speaking rather than merely at some point.
  final List<String> ordering;

  final List<String> spoken = [];
  int stopCount = 0;

  /// Holds each utterance open, so a test can act mid-playback.
  bool hold = false;
  final List<Completer<TtsSpeakOutcome>> pending = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> init({String? language}) async {}

  @override
  Future<List<String>> getLanguages() async => const ['en-US'];

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      languageAvailable;

  @override
  Future<void> setSpeechRateMultiplier(double multiplier) async {}

  @override
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    spoken.add(text);
    ordering.add('speak');
    if (!hold) return TtsSpeakOutcome.completed;
    final completer = Completer<TtsSpeakOutcome>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<bool> pause() async => true;

  @override
  Future<void> stop() async {
    stopCount++;
    ordering.add('tts.stop');
  }
}

/// An STT service the test drives directly: it records what the screen asked
/// for and delivers the recognition callbacks by hand, in the order the plugin
/// would.
class _FakeSttService extends SttService {
  _FakeSttService({
    required super.logger,
    this.localeId = 'en_US',
    this.startResult = SttStartResult.started,
    List<String>? ordering,
  }) : ordering = ordering ?? [],
       super(
         speech: SpeechToText.withMethodChannel(),
         platform: PlatformInfo.android,
       );

  /// What `resolveLocaleId` answers; null means the device has no locale for
  /// the story's language.
  final String? localeId;

  /// What `listen` answers, so every start outcome is reachable.
  final SttStartResult startResult;

  SttListener? listener;
  final List<String> listened = [];
  int stopCount = 0;
  int cancelCount = 0;

  /// The order in which the screen stopped playback, closed the recognizer and
  /// opened the mic, so the test can prove the two never overlap. Shared with
  /// the TTS fake.
  final List<String> ordering;

  /// A previous session's final result, delivered from inside `cancel()`.
  ///
  /// That is where the real one arrives: the platform channel is ordered, so an
  /// event the old session already queued reaches Dart before the cancel's own
  /// reply does.
  String? staleFinalOnCancel;

  /// Holds `cancel()` open. That await is the window in which Record is still
  /// on screen, the session not being recording yet.
  Completer<void>? holdCancel;

  @override
  Future<SttInitResult> initialize() async => SttInitResult.ready;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<String?> resolveLocaleId(String languageCode) async => localeId;

  /// Holds `listen()` open, so a test can act while a start is unconfirmed.
  /// `cancel()` resolves it as cancelled, the way the service invalidates a
  /// pending start.
  Completer<SttStartResult>? holdListen;

  @override
  Future<SttStartResult> listen({required String localeId}) async {
    listened.add(localeId);
    ordering.add('listen');
    final gate = holdListen;
    if (gate != null) return gate.future;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    ordering.add('stt.stop');
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    ordering.add('cancel');
    final pendingStart = holdListen;
    if (pendingStart != null && !pendingStart.isCompleted) {
      pendingStart.complete(SttStartResult.cancelled);
    }
    final gate = holdCancel;
    if (gate != null) await gate.future;
    final stale = staleFinalOnCancel;
    if (stale != null) {
      staleFinalOnCancel = null;
      listener?.onSttResult(stale, isFinal: true);
    }
  }

  @override
  void attach(SttListener listener) {
    this.listener = listener;
  }

  @override
  void detach(SttListener listener) {
    if (this.listener != listener) return;
    this.listener = null;
    cancel();
  }

  void emitPartial(String transcript) =>
      listener?.onSttResult(transcript, isFinal: false);

  void emitFinal(String transcript) =>
      listener?.onSttResult(transcript, isFinal: true);

  void emitDone() => listener?.onSttDone();

  void emitError(SttErrorKind kind) => listener?.onSttError(kind);
}

/// A permission service with a scripted verdict, so every branch of the
/// microphone flow is reachable without a device.
class _FakePermissionService extends MicPermissionService {
  _FakePermissionService({
    required super.sttService,
    required super.logger,
    this.statusResult = MicPermission.granted,
    List<MicRequestOutcome> outcomes = const [MicRequestOutcome.granted],
  }) : _outcomes = List.of(outcomes),
       super(platform: PlatformInfo.android);

  final MicPermission statusResult;

  /// Consumed one per `request()`; the last one repeats, so a retry can be
  /// scripted to succeed.
  final List<MicRequestOutcome> _outcomes;

  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<MicPermission> status() async => statusResult;

  @override
  Future<MicRequestOutcome> request() async {
    requestCount++;
    return _outcomes.length == 1 ? _outcomes.first : _outcomes.removeAt(0);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    return true;
  }
}

void main() {
  // The story audio controller restores the remembered speech rate from
  // preferences on prepare(); give it a deterministic empty store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const story =
      'The morning air was cold and clean. '
      'She walked to the river without speaking.';

  const firstSentence = 'The morning air was cold and clean.';

  Story storyWith(String content, {String language = 'en'}) => Story(
    id: 1,
    userId: 1,
    content: content,
    storyWords: 'run',
    learningLanguage: language,
    firstReadAt: 1700000000,
    favoriteCount: 0,
    createdAt: 1700000000,
  );

  late MockAppLogger logger;

  setUp(() => logger = MockAppLogger());

  /// Builds the screen with every seam injected.
  Future<
    ({
      _FakeTtsService tts,
      _FakeSttService stt,
      _FakePermissionService permissions,
      List<String> ordering,
      StoryAudioController audio,
    })
  >
  pumpScreen(
    WidgetTester tester, {
    String content = story,
    String language = 'en',
    bool languageAvailable = true,
    String? localeId = 'en_US',
    SttStartResult startResult = SttStartResult.started,
    MicPermission status = MicPermission.granted,
    List<MicRequestOutcome> outcomes = const [MicRequestOutcome.granted],
    PlatformInfo platform = PlatformInfo.android,
    bool isActive = true,
  }) async {
    final ordering = <String>[];
    final tts = _FakeTtsService(
      languageAvailable: languageAvailable,
      ordering: ordering,
    );
    final stt = _FakeSttService(
      logger: logger,
      localeId: localeId,
      startResult: startResult,
      ordering: ordering,
    );
    final permissions = _FakePermissionService(
      sttService: stt,
      logger: logger,
      statusResult: status,
      outcomes: outcomes,
    );

    final storyUnderTest = storyWith(content, language: language);
    // Hosted the way `StoryDetailScreen` hosts it: one controller and one
    // exercise set, owned outside the view and prepared before it mounts.
    final audio = StoryAudioController.forContent(
      ttsService: tts,
      languageCode: storyUnderTest.learningLanguage,
      content: storyUnderTest.content,
    );
    await audio.prepare();
    addTearDown(audio.dispose);
    // The host's own probe is not the view's doing; the ordering assertions
    // start from the view.
    ordering.clear();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SpeakingView(
            story: storyUnderTest,
            audio: audio,
            items: ListeningSetBuilder.build(
              languageCode: storyUnderTest.learningLanguage,
              sentences: audio.sentences,
            ),
            isActive: isActive,
            sttService: stt,
            permissions: permissions,
            platform: platform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      tts: tts,
      stt: stt,
      permissions: permissions,
      ordering: ordering,
      audio: audio,
    );
  }

  /// Taps a button by its label, scrolling it into view first: the exercise
  /// column is taller than the test viewport.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps a button inside the rationale dialog. Its label matches the CTA
  /// behind it, so the finder has to say which one it means.
  Future<void> tapDialogButton(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  /// Taps while recording. The recording indicator animates forever, so
  /// `pumpAndSettle` would never return.
  Future<void> tapWhileRecording(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Starts a recording and leaves it running.
  Future<void> startRecording(WidgetTester tester) async {
    await tester.tap(find.text('Record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// The button carrying [label]. `FilledButton.icon` builds a private
  /// subclass, so the match is on the base type rather than an exact one.
  ButtonStyleButton buttonWith(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );

  /// Settles the screen after recognition ended, once the indicator is gone.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('platform gate', () {
    testWidgets(
      'an unsupported platform explains itself and touches no plugin',
      (tester) async {
        const ttsChannel = MethodChannel('flutter_tts');
        const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
        const permissionChannel = MethodChannel(
          'flutter.baseflow.com/permissions/methods',
        );
        final calls = <String>[];

        for (final channel in [ttsChannel, sttChannel, permissionChannel]) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                calls.add('${channel.name}#${call.method}');
                return null;
              });
        }
        addTearDown(() {
          for (final channel in [ttsChannel, sttChannel, permissionChannel]) {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null);
          }
        });

        // The production services, so the assertion covers the audio controller
        // and both services rather than a fake standing in for them.
        final tts = TtsService(logger: logger);
        final stt = SttService(logger: logger, platform: PlatformInfo.linux);
        final permissions = MicPermissionService(
          sttService: stt,
          logger: logger,
          platform: PlatformInfo.linux,
        );
        // Constructing the plugin objects is not the screen's doing.
        calls.clear();

        final storyUnderTest = storyWith(story);
        final audio = StoryAudioController.forContent(
          ttsService: tts,
          languageCode: storyUnderTest.learningLanguage,
          content: storyUnderTest.content,
        );
        addTearDown(audio.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SpeakingView(
                story: storyUnderTest,
                audio: audio,
                items: ListeningSetBuilder.build(
                  languageCode: storyUnderTest.learningLanguage,
                  sentences: audio.sentences,
                ),
                sttService: stt,
                permissions: permissions,
                platform: PlatformInfo.linux,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Speaking practice is available on Android and iOS only'),
          findsOneWidget,
        );
        expect(find.text('Record'), findsNothing);
        expect(calls, isEmpty);
      },
    );
  });

  group('blocked states', () {
    testWidgets('no voice for the story language', (tester) async {
      await pumpScreen(tester, languageAvailable: false);

      expect(
        find.textContaining('No text-to-speech voice is available'),
        findsOneWidget,
      );
      expect(find.text('Record'), findsNothing);
    });

    testWidgets('the recognizer does not support the story language', (
      tester,
    ) async {
      await pumpScreen(tester, localeId: null);

      expect(
        find.textContaining('does not support this story\'s language'),
        findsOneWidget,
      );
    });

    testWidgets('a story with nothing long enough to practise', (tester) async {
      await pumpScreen(tester, content: 'Too short. No. Yes.');

      expect(find.textContaining('no sentence long enough'), findsOneWidget);
    });

    testWidgets('an unavailable recognizer offers a retry that recovers', (
      tester,
    ) async {
      final harness = await pumpScreen(
        tester,
        outcomes: const [
          MicRequestOutcome.recognizerUnavailable,
          MicRequestOutcome.granted,
        ],
      );

      expect(
        find.textContaining('No speech recognizer is available'),
        findsOneWidget,
      );

      await tapButton(tester, 'Try again');

      expect(harness.permissions.requestCount, 2);
      expect(find.text('Record'), findsOneWidget);
    });
  });

  group('microphone permission', () {
    testWidgets('a denied status asks, behind a rationale', (tester) async {
      final harness = await pumpScreen(tester, status: MicPermission.denied);

      expect(
        find.text('Speaking practice needs microphone access'),
        findsOneWidget,
      );
      // Nothing was requested on entry: the ask is the user's move.
      expect(harness.permissions.requestCount, 0);

      await tapButton(tester, 'Allow microphone');

      // The rationale, then the request.
      expect(find.text('Microphone access'), findsOneWidget);
      await tapDialogButton(tester, 'Allow microphone');

      expect(harness.permissions.requestCount, 1);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('declining the rationale asks for nothing', (tester) async {
      final harness = await pumpScreen(tester, status: MicPermission.denied);

      await tapButton(tester, 'Allow microphone');
      await tapButton(tester, 'Not now');

      expect(harness.permissions.requestCount, 0);
      expect(find.text('Record'), findsNothing);
    });

    testWidgets('a refused request keeps the ask available', (tester) async {
      final harness = await pumpScreen(
        tester,
        status: MicPermission.denied,
        outcomes: const [MicRequestOutcome.denied],
      );

      await tapButton(tester, 'Allow microphone');
      await tapDialogButton(tester, 'Allow microphone');

      expect(harness.permissions.requestCount, 1);
      expect(
        find.text('Speaking practice needs microphone access'),
        findsOneWidget,
      );
    });

    testWidgets('a permanently denied status offers settings', (tester) async {
      final harness = await pumpScreen(
        tester,
        status: MicPermission.permanentlyDenied,
      );

      expect(
        find.textContaining('Microphone access is turned off'),
        findsOneWidget,
      );

      await tapButton(tester, 'Open settings');

      expect(harness.permissions.openSettingsCount, 1);
    });

    testWidgets(
      'a request that comes back permanently denied switches the CTA',
      (tester) async {
        final harness = await pumpScreen(
          tester,
          status: MicPermission.denied,
          outcomes: const [MicRequestOutcome.permanentlyDenied],
        );

        await tapButton(tester, 'Allow microphone');
        await tapDialogButton(tester, 'Allow microphone');

        await tapButton(tester, 'Open settings');
        expect(harness.permissions.openSettingsCount, 1);
      },
    );
  });

  group('exercise flow', () {
    testWidgets('shows the first sentence and plays it on request', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      expect(find.text(firstSentence), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      // Nothing is spoken until asked: the microphone comes first here.
      expect(harness.tts.spoken, isEmpty);

      await tapButton(tester, 'Play');

      expect(harness.tts.spoken, [firstSentence]);
      expect(find.text('Replay'), findsOneWidget);
    });

    testWidgets(
      'records, shows the partial transcript, then scores the final',
      (tester) async {
        final harness = await pumpScreen(tester);

        await startRecording(tester);
        expect(find.text('Listening to you…'), findsOneWidget);
        expect(find.text('Stop'), findsOneWidget);
        expect(harness.stt.listened, ['en_US']);

        harness.stt.emitPartial('the morning air');
        await tester.pump();
        expect(find.text('the morning air'), findsOneWidget);

        harness.stt.emitFinal('the morning air was cold and clean');
        await settle(tester);

        expect(find.text('Well said'), findsOneWidget);
        expect(find.text('Word accuracy: 100%'), findsOneWidget);
        expect(find.text('Missing'), findsOneWidget);
        expect(find.text('Extra'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
      },
    );

    testWidgets('an explicit Stop scores what was recognized', (tester) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitPartial('the morning air was cold');
      await tester.pump();

      await tapWhileRecording(tester, 'Stop');
      expect(harness.stt.stopCount, 1);

      // The platform's final result lands after the stop, as it does on device.
      harness.stt.emitFinal('the morning air was cold');
      await settle(tester);

      expect(find.text('Almost there'), findsOneWidget);
    });

    testWidgets('a stop with no final result scores the last partial', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitPartial('the morning air was cold and clean');
      await tester.pump();

      harness.stt.emitDone();
      await settle(tester);

      expect(find.text('Well said'), findsOneWidget);
    });

    testWidgets('a silent session says so and stays retryable', (tester) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitDone();
      await settle(tester);

      expect(find.textContaining('Nothing was heard'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('an empty final transcript is treated as silence', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitFinal('   ');
      await settle(tester);

      expect(find.textContaining('Nothing was heard'), findsOneWidget);
    });

    testWidgets('retry clears the attempt', (tester) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitFinal('completely unrelated words');
      await settle(tester);
      expect(find.text('Not quite'), findsOneWidget);

      await tapButton(tester, 'Say it again');

      expect(find.text('Not quite'), findsNothing);
      expect(find.text('completely unrelated words'), findsNothing);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('next advances without speaking on its own', (tester) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitFinal('the morning air was cold and clean');
      await settle(tester);

      await tapButton(tester, 'Next');

      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        find.text('She walked to the river without speaking.'),
        findsOneWidget,
      );
      // The reference is only ever spoken on request.
      expect(harness.tts.spoken, isEmpty);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);
    });

    testWidgets('a late transcript after an abandoned attempt is ignored', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitError(SttErrorKind.noSpeech);
      await settle(tester);

      // The plugin's final result, arriving behind the error.
      harness.stt.emitFinal('the morning air was cold and clean');
      await settle(tester);

      expect(find.textContaining('Nothing was heard'), findsOneWidget);
      expect(find.text('Well said'), findsNothing);
    });

    testWidgets('a previous attempt\'s final result cannot score the next', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitError(SttErrorKind.noSpeech);
      await settle(tester);

      // Queued by the abandoned attempt and flushed by the cancel that opens
      // the next one — the only point at which it can still arrive.
      harness.stt.staleFinalOnCancel = 'the morning air was cold and clean';
      await startRecording(tester);

      // The new attempt is recording and unscored: the stale words did not
      // become its answer.
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Well said'), findsNothing);
      expect(find.textContaining('Word accuracy'), findsNothing);

      // And this attempt's own words are still scored normally.
      harness.stt.emitFinal('the morning air was cold');
      await settle(tester);
      expect(find.textContaining('Word accuracy'), findsOneWidget);
    });

    testWidgets('a double tap on Record starts one recording, not two', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      // The reachable window: the start is awaiting the recogniser's cancel,
      // so the session is not recording yet and Record is still on screen.
      final gate = Completer<void>();
      harness.stt.holdCancel = gate;

      await tester.tap(find.text('Record'));
      await tester.pump();
      expect(find.text('Record'), findsOneWidget);

      await tester.tap(find.text('Record'));
      await tester.pump();

      harness.stt.holdCancel = null;
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.stt.listened, hasLength(1));
      expect(harness.stt.cancelCount, 1);
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('a new attempt closes the previous session before listening', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);

      expect(
        harness.stt.ordering,
        containsAllInOrder(['tts.stop', 'cancel', 'listen']),
      );
    });

    testWidgets('the last sentence finishes into a summary', (tester) async {
      final harness = await pumpScreen(tester);

      await startRecording(tester);
      harness.stt.emitFinal('the morning air was cold and clean');
      await settle(tester);
      await tapButton(tester, 'Next');

      await startRecording(tester);
      harness.stt.emitFinal('she walked to the river without speaking');
      await settle(tester);
      expect(find.text('Finish'), findsOneWidget);

      await tapButton(tester, 'Finish');

      expect(find.text('Set complete'), findsOneWidget);
      expect(find.text('Said well: 2 / 2'), findsOneWidget);

      await tapButton(tester, 'Practise again');
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('recognition failures', () {
    // One test per cause: pumping a second screen of the same type inside one
    // test would reuse the State and never run initState again.
    const causes = {
      SttErrorKind.busy: 'The speech recognizer is busy',
      SttErrorKind.noMic: 'The microphone is not available',
      SttErrorKind.network: 'needs a network connection',
      SttErrorKind.noSpeech: 'Nothing was heard',
      SttErrorKind.languageUnavailable: 'cannot recognize this story',
      SttErrorKind.other: 'Speech recognition failed',
    };

    for (final entry in causes.entries) {
      testWidgets('${entry.key.name} has its own message', (tester) async {
        final harness = await pumpScreen(tester);
        await startRecording(tester);

        harness.stt.emitError(entry.key);
        await settle(tester);

        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.text('Record'), findsOneWidget);
      });
    }

    testWidgets('a permission error mid-session returns to the ask', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);

      harness.stt.emitError(SttErrorKind.permission);
      await settle(tester);

      expect(
        find.text('Speaking practice needs microphone access'),
        findsOneWidget,
      );
    });

    testWidgets('a busy recognizer says so, not something generic', (
      tester,
    ) async {
      await pumpScreen(tester, startResult: SttStartResult.busy);

      await tapButton(tester, 'Record');

      expect(find.textContaining('recognizer is busy'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('a start the platform reports as failed is reported', (
      tester,
    ) async {
      await pumpScreen(tester, startResult: SttStartResult.failed);

      await tapButton(tester, 'Record');

      expect(find.textContaining('Speech recognition failed'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
    });
  });

  group('playback and recognition never overlap', () {
    testWidgets('recording stops playback first', (tester) async {
      final harness = await pumpScreen(tester);
      await tapButton(tester, 'Play');
      final stopsBefore = harness.tts.stopCount;

      await startRecording(tester);

      expect(harness.tts.stopCount, greaterThan(stopsBefore));
      expect(harness.stt.listened, isNotEmpty);
    });

    testWidgets('Play is disabled while recording', (tester) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);

      expect(buttonWith(tester, 'Play').onPressed, isNull);
      expect(harness.tts.spoken, isEmpty);
    });

    testWidgets('Play closes the recognizer before speaking, even after a '
        'final result', (tester) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);

      // Scored, but the platform recognizer keeps running until its own
      // terminal status — the window in which a tap could overlap the two.
      harness.stt.emitFinal('the morning air was cold and clean');
      await settle(tester);
      expect(harness.stt.stopCount, 0);

      await tapButton(tester, 'Play');

      expect(harness.tts.spoken, isNotEmpty);
      final cancel = harness.ordering.lastIndexOf('cancel');
      final speak = harness.ordering.lastIndexOf('speak');
      expect(cancel, greaterThanOrEqualTo(0));
      expect(cancel, lessThan(speak));
    });

    testWidgets('Record is disabled while the reference is playing', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      harness.tts.hold = true;

      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump();

      expect(buttonWith(tester, 'Record').onPressed, isNull);

      // Let the held utterance finish so the screen can be disposed cleanly.
      harness.tts.pending.single.complete(TtsSpeakOutcome.completed);
      await tester.pumpAndSettle();
    });
  });

  group('lifecycle', () {
    testWidgets('backgrounding cancels the recording', (tester) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);

      expect(harness.stt.cancelCount, greaterThanOrEqualTo(1));
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('pausing during Play never starts the reference', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      // Play awaits the recogniser's cancel first; the app leaves the
      // foreground while that is in flight.
      final gate = Completer<void>();
      harness.stt.holdCancel = gate;

      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(harness.tts.spoken, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      harness.stt.holdCancel = null;
      gate.complete();
      await tester.pumpAndSettle();

      // The continuation resumed in the background and must not have spoken.
      expect(harness.tts.spoken, isEmpty);
    });

    testWidgets('pausing during a start never opens the microphone', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      final gate = Completer<void>();
      harness.stt.holdCancel = gate;

      await tester.tap(find.text('Record'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      harness.stt.holdCancel = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(harness.stt.listened, isEmpty);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('pausing while a start is unconfirmed abandons it quietly', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      // Unconfirmed: the platform has not said whether it is listening.
      harness.stt.holdListen = Completer<SttStartResult>();

      await startRecording(tester);
      expect(harness.stt.listened, hasLength(1));

      // The lifecycle handler's cancel is what invalidates the pending start,
      // so the start resolves as cancelled rather than as a refusal.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      // No error copy for something the user did on purpose.
      expect(find.text('Record'), findsOneWidget);
      expect(find.textContaining('recognizer is busy'), findsNothing);
      expect(find.textContaining('Speech recognition failed'), findsNothing);
    });

    testWidgets('backgrounding stops the reference utterance too', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      harness.tts.hold = true;

      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump();
      expect(harness.tts.pending, hasLength(1));
      final stopsBefore = harness.tts.stopCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(harness.tts.stopCount, greaterThan(stopsBefore));

      harness.tts.pending.single.complete(TtsSpeakOutcome.completed);
      await tester.pumpAndSettle();
    });

    testWidgets('unmounting cancels the recording and detaches', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);

      // Starting the recording already cancelled once, closing whatever the
      // previous attempt left open, so the unmount's own cancel is the increase.
      final cancelsBefore = harness.stt.cancelCount;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(harness.stt.cancelCount, greaterThan(cancelsBefore));
      expect(harness.stt.listener, isNull);
      expect(harness.tts.stopCount, greaterThanOrEqualTo(1));
    });

    testWidgets('popping the route cancels the recording', (tester) async {
      final tts = _FakeTtsService();
      final stt = _FakeSttService(logger: logger);
      final permissions = _FakePermissionService(
        sttService: stt,
        logger: logger,
      );
      final audio = StoryAudioController.forContent(
        ttsService: tts,
        languageCode: 'en',
        content: story,
      );
      await audio.prepare();
      addTearDown(audio.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => Scaffold(
                                  body: SpeakingView(
                                    story: storyWith(story),
                                    audio: audio,
                                    items: ListeningSetBuilder.build(
                                      languageCode: 'en',
                                      sentences: audio.sentences,
                                    ),
                                    sttService: stt,
                                    permissions: permissions,
                                    platform: PlatformInfo.android,
                                  ),
                                ),
                          ),
                        ),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      );
      await tapButton(tester, 'open');
      await startRecording(tester);
      final cancelsBefore = stt.cancelCount;

      Navigator.of(tester.element(find.text('Stop'))).pop();
      await tester.pumpAndSettle();

      expect(stt.cancelCount, greaterThan(cancelsBefore));
      expect(stt.listener, isNull);
    });

    testWidgets('a callback arriving after detach changes nothing', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      await startRecording(tester);
      final listener = harness.stt.listener!;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // The plugin's last event, delivered to a screen that is already gone.
      listener.onSttResult('too late', isFinal: true);
      listener.onSttDone();
      listener.onSttError(SttErrorKind.busy);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('too late'), findsNothing);
    });
  });

  group('the host owns the controller and the mode', () {
    testWidgets('deactivating cancels the recording and leaves Record inert', (
      tester,
    ) async {
      final ordering = <String>[];
      final tts = _FakeTtsService(ordering: ordering);
      final stt = _FakeSttService(logger: logger, ordering: ordering);
      final permissions = _FakePermissionService(
        sttService: stt,
        logger: logger,
      );
      final storyUnderTest = storyWith(story);
      final audio = StoryAudioController.forContent(
        ttsService: tts,
        languageCode: storyUnderTest.learningLanguage,
        content: storyUnderTest.content,
      );
      await audio.prepare();
      addTearDown(audio.dispose);
      // The host's switcher, reduced to the one input the view reads.
      final active = ValueNotifier<bool>(true);
      addTearDown(active.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder:
                  (_, isActive, __) => SpeakingView(
                    story: storyUnderTest,
                    audio: audio,
                    items: ListeningSetBuilder.build(
                      languageCode: storyUnderTest.learningLanguage,
                      sentences: audio.sentences,
                    ),
                    isActive: isActive,
                    sttService: stt,
                    permissions: permissions,
                    platform: PlatformInfo.android,
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await startRecording(tester);
      final cancelsBefore = stt.cancelCount;
      final listensBefore = stt.listened.length;

      active.value = false;
      await tester.pumpAndSettle();

      // The recognizer is closed and the attempt abandoned: Stop is gone and
      // the sentence is offered again.
      expect(stt.cancelCount, greaterThan(cancelsBefore));
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Record'), findsOneWidget);

      // Still mounted behind another mode: a tap that reaches it opens nothing.
      await tapButton(tester, 'Record');
      expect(stt.listened.length, listensBefore);
    });

    testWidgets('the injected controller is stopped, never disposed', (
      tester,
    ) async {
      final harness = await pumpScreen(tester);
      final audio = harness.audio;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(harness.tts.stopCount, greaterThanOrEqualTo(1));

      // A disposed controller would throw on notify; the host can still drive
      // this one, which is the proof the view left it alive.
      harness.tts.spoken.clear();
      await audio.playSentence(0);
      expect(harness.tts.spoken, hasLength(1));
      expect(audio.state, StoryPlaybackState.idle);
    });
  });
}
