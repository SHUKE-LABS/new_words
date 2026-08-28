import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/stories_api_v2.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/presentation/listening_view.dart';
import 'package:new_words/features/practice/presentation/speaking_view.dart';
import 'package:new_words/features/stories/presentation/story_detail_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/stories_provider.dart';
import 'package:new_words/services/mic_permission_service.dart';
import 'package:new_words/services/stories_service_v2.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/utils/platform_info.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/mock_app_logger.dart';

/// A TTS service that never touches a platform channel, so the screen's wiring
/// can be driven off-device: what it was asked to speak, and in what order, is
/// what the assertions read.
class _FakeTtsService extends TtsService {
  _FakeTtsService({
    this.supported = true,
    this.availableLanguages = const ['en-US'],
  });

  final bool supported;
  final List<String> availableLanguages;

  final List<String> spoken = [];
  int stopCount = 0;
  int pauseCount = 0;
  final List<double> rates = [];

  /// How many times the capability probe ran. One controller over one story
  /// means one probe, however often the mode changes.
  int languageProbes = 0;

  /// Playback, recognition and screen-reader events in the order they
  /// happened, shared with the STT spy and the announcement handler: what the
  /// switch has to guarantee is an order, not a set of counts.
  final List<String> ordering = [];

  /// Set to hold the current utterance open, so a test can observe the
  /// highlight while a sentence is "playing".
  bool hold = false;
  final List<Completer<TtsSpeakOutcome>> pending = [];

  @override
  bool get isSupported => supported;

  @override
  Future<void> init({String? language}) async {}

  /// Holds the capability probe open, so a test can switch modes while the
  /// host's `prepare()` is still in flight.
  Completer<List<String>>? holdLanguages;

  @override
  Future<List<String>> getLanguages() async {
    languageProbes++;
    final gate = holdLanguages;
    if (gate != null) return gate.future;
    return availableLanguages;
  }

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      availableLanguages.isNotEmpty;

  @override
  Future<void> setSpeechRateMultiplier(double multiplier) async {
    rates.add(multiplier);
  }

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
  Future<bool> pause() async {
    pauseCount++;
    return true;
  }

  /// Holds `stop()` open, so a test can observe what the caller does — or
  /// must not do — while the stop is still pending.
  Completer<void>? blockStop;

  @override
  Future<void> stop() async {
    stopCount++;
    ordering.add('tts.stop');
    final gate = blockStop;
    if (gate != null) await gate.future;
  }
}

/// Counts every microphone-facing call, so Read and Listen can be proven never
/// to make one, and behaves like a working recognizer once Speak is selected.
class _SpySttService extends SttService {
  _SpySttService({required super.logger, required this.ordering})
    : super(
        speech: SpeechToText.withMethodChannel(),
        platform: PlatformInfo.android,
      );

  final List<String> ordering;

  int initializeCount = 0;
  int attachCount = 0;
  int detachCount = 0;
  int cancelCount = 0;
  final List<String> listened = [];
  SttListener? listener;

  @override
  Future<SttInitResult> initialize() async {
    initializeCount++;
    return SttInitResult.ready;
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<String?> resolveLocaleId(String languageCode) async => 'en_US';

  @override
  Future<SttStartResult> listen({required String localeId}) async {
    listened.add(localeId);
    ordering.add('listen');
    return SttStartResult.started;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    cancelCount++;
    ordering.add('stt.cancel');
  }

  @override
  void attach(SttListener listener) {
    attachCount++;
    this.listener = listener;
  }

  @override
  void detach(SttListener listener) {
    if (this.listener != listener) return;
    detachCount++;
    this.listener = null;
    cancel();
  }
}

class _SpyPermissionService extends MicPermissionService {
  _SpyPermissionService({required super.sttService, required super.logger})
    : super(platform: PlatformInfo.android);

  int statusCount = 0;
  int requestCount = 0;

  @override
  Future<MicPermission> status() async {
    statusCount++;
    return MicPermission.granted;
  }

  @override
  Future<MicRequestOutcome> request() async {
    requestCount++;
    return MicRequestOutcome.granted;
  }
}

void main() {
  setUpAll(() {
    // AppConfig.isProduction reads dotenv, and the screen's app bar consults it.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  // The story audio controller restores the remembered speech rate from
  // preferences on prepare(); give it a deterministic empty store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakeTtsService tts;
  late _SpySttService stt;
  late _SpyPermissionService permissions;
  late StoriesProvider provider;

  Story storyWith(String content) => Story(
    id: 1,
    userId: 1,
    content: content,
    storyWords: 'calm',
    learningLanguage: 'en',
    // Already read, so the screen's post-frame callback does not call the
    // API to mark it read.
    firstReadAt: 1700000000,
    favoriteCount: 0,
    createdAt: 1700000000,
  );

  void register<T extends Object>(T service) {
    if (GetIt.I.isRegistered<T>()) {
      GetIt.I.unregister<T>();
    }
    GetIt.I.registerSingleton<T>(service);
  }

  setUp(() {
    tts = _FakeTtsService();
    register<TtsService>(tts);
    stt = _SpySttService(logger: MockAppLogger(), ordering: tts.ordering);
    permissions = _SpyPermissionService(
      sttService: stt,
      logger: MockAppLogger(),
    );
    register<SttService>(stt);
    register<MicPermissionService>(permissions);
    provider = StoriesProvider(
      StoriesServiceV2(
        storiesApi: StoriesApiV2(Dio()),
        logger: MockAppLogger(),
      ),
    );
  });

  tearDown(() {
    GetIt.I.unregister<TtsService>();
    GetIt.I.unregister<SttService>();
    GetIt.I.unregister<MicPermissionService>();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Story story, {
    Locale? locale,
  }) async {
    // Screen-reader announcements go out on this channel; recording them in the
    // shared log is what lets a test assert what happened *before* one.
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        tts.ordering.add('announce');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StoriesProvider>.value(
        value: provider,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StoryDetailScreen(
            story: story,
            sttService: stt,
            permissions: permissions,
            platform: PlatformInfo.android,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A switcher segment by its label. Scoped, because the story body carries
  /// its own "Read" — the read/unread status — and would otherwise match.
  Finder modeSegment(String label) => find.descendant(
    of: find.byType(SegmentedButton<PracticeMode>),
    matching: find.text(label),
  );

  /// Switches practice mode through the switcher, the way a user does.
  Future<void> selectMode(WidgetTester tester, String label) async {
    await tester.tap(modeSegment(label));
    await tester.pumpAndSettle();
  }

  /// Pumps a fixed number of frames. Used wherever a mode is still waiting on
  /// a probe: its spinner animates forever, so `pumpAndSettle` never returns.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Switches modes without settling, and pumps enough frames for the switch's
  /// own awaits to run.
  Future<void> selectModeWhileWaiting(WidgetTester tester, String label) async {
    await tester.tap(modeSegment(label));
    await pumpFrames(tester);
  }

  /// Every distinct tap recognizer in the rendered story content, in the order
  /// the spans appear — one per sentence.
  List<TapGestureRecognizer> recognizersInOrder(WidgetTester tester) {
    final text = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(SelectionArea),
            matching: find.byType(Text),
          )
          .first,
    );
    final found = <TapGestureRecognizer>[];
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        final recognizer = span.recognizer;
        if (recognizer is TapGestureRecognizer && !found.contains(recognizer)) {
          found.add(recognizer);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }

    visit(text.textSpan!);
    return found;
  }

  group('StoryDetailScreen read-aloud', () {
    testWidgets('renders the player bar with play, stop and rate controls', (
      tester,
    ) async {
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('play speaks every sentence in order', (tester) async {
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(tts.spoken, ['She waited.', 'Then it rained.']);
    });

    testWidgets('tapping a sentence plays that sentence, by index', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        storyWith('First one. Second **two**. Third three.'),
      );

      final recognizers = recognizersInOrder(tester);
      expect(
        recognizers.length,
        3,
        reason: 'one recognizer per sentence, shared by its spans',
      );

      // The middle sentence spans three TextSpans (plain, bold, plain); its
      // recognizer must still play sentence 1, not the span's ordinal.
      recognizers[1].onTap!();
      await tester.pumpAndSettle();

      expect(tts.spoken, ['Second two.']);
    });

    testWidgets(
      'the playing sentence is highlighted and cleared when it ends',
      (tester) async {
        tts.hold = true;
        await pumpScreen(tester, storyWith('She waited. Then it rained.'));

        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();

        Color? backgroundOf(int spanIndex) {
          final text = tester.widget<Text>(
            find
                .descendant(
                  of: find.byType(SelectionArea),
                  matching: find.byType(Text),
                )
                .first,
          );
          final children = (text.textSpan! as TextSpan).children!;
          return (children[spanIndex] as TextSpan).style?.backgroundColor;
        }

        expect(backgroundOf(0), isNotNull, reason: 'sentence 0 is playing');
        expect(backgroundOf(1), isNull);

        // Finish sentence 0; the highlight moves on, then clears at the end.
        tts.pending.removeAt(0).complete(TtsSpeakOutcome.completed);
        await tester.pump();
        expect(backgroundOf(0), isNull);
        expect(backgroundOf(1), isNotNull);

        tts.pending.removeAt(0).complete(TtsSpeakOutcome.completed);
        await tester.pump();
        expect(backgroundOf(0), isNull);
        expect(
          backgroundOf(1),
          isNull,
          reason: 'the highlight clears at the end',
        );
      },
    );

    testWidgets('pause and stop drive the service and the button icon', (
      tester,
    ) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(tts.pauseCount, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(tts.stopCount, greaterThan(0));
    });

    testWidgets('stop is disabled while idle', (tester) async {
      await pumpScreen(tester, storyWith('She waited.'));

      final stop = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.stop),
          matching: find.byType(IconButton),
        ),
      );
      expect(stop.onPressed, isNull);
    });

    testWidgets(
      'an unsupported platform disables the controls and explains why',
      (tester) async {
        final unsupported = _FakeTtsService(supported: false);
        register<TtsService>(unsupported);
        await pumpScreen(tester, storyWith('She waited.'));

        final rate = tester.widget<PopupMenuButton<double>>(
          find.byType(PopupMenuButton<double>),
        );
        expect(rate.enabled, isFalse);

        // Play stays tappable so it can explain itself instead of doing nothing.
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        expect(unsupported.spoken, isEmpty);
        expect(
          find.text('Read aloud is not available on this device'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a device with no voices reports that, not unsupported', (
      tester,
    ) async {
      final noVoices = _FakeTtsService(availableLanguages: const []);
      register<TtsService>(noVoices);
      await pumpScreen(tester, storyWith('She waited.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(noVoices.spoken, isEmpty);
      expect(
        find.text('No text-to-speech voice is installed on this device'),
        findsOneWidget,
      );
    });

    testWidgets('leaving the screen stops playback without disposing the '
        'shared service', (tester) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      final stopsBefore = tts.stopCount;

      // Replace the screen: State.dispose runs.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
      expect(
        GetIt.I.isRegistered<TtsService>(),
        isTrue,
        reason: 'the singleton is shared with word detail and must survive',
      );
    });
  });

  const practiceStory =
      'She waited for a long time. Then it rained on the roof.';

  group('StoryDetailScreen mode switcher', () {
    testWidgets('offers Read, Listen and Speak, and shows the one selected', (
      tester,
    ) async {
      await pumpScreen(tester, storyWith(practiceStory));

      expect(modeSegment('Read'), findsOneWidget);
      expect(modeSegment('Listen'), findsOneWidget);
      expect(modeSegment('Speak'), findsOneWidget);
      // Read is the mode on arrival: its player bar is there, no exercise is.
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(ListeningView), findsNothing);

      await selectMode(tester, 'Listen');
      expect(find.byType(ListeningView), findsOneWidget);
      expect(find.text('Listen and type the whole sentence'), findsOneWidget);

      await selectMode(tester, 'Speak');
      expect(find.byType(SpeakingView), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('the player bar belongs to Read alone', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));
      expect(find.byIcon(Icons.stop), findsOneWidget);

      await selectMode(tester, 'Listen');
      expect(find.byIcon(Icons.stop), findsNothing);

      await selectMode(tester, 'Read');
      expect(find.byIcon(Icons.stop), findsOneWidget);
    });

    testWidgets('Read to Listen to Speak and back re-uses one controller and '
        'one segmentation', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));

      await selectMode(tester, 'Listen');
      // Listen opens by speaking its first item.
      final firstPass = List.of(tts.spoken);
      expect(firstPass, ['She waited for a long time.']);
      expect(find.text('1 / 2'), findsOneWidget);

      await selectMode(tester, 'Speak');
      await selectMode(tester, 'Read');
      await selectMode(tester, 'Listen');

      // One probe for the whole round trip: no mode built a controller of its
      // own, so no mode re-segmented the story either.
      expect(tts.languageProbes, 1);
      // The exercise set survived the round trip rather than being rebuilt.
      expect(find.text('1 / 2'), findsOneWidget);

      tts.spoken.clear();
      await tester.tap(find.text('Replay'));
      await tester.pumpAndSettle();
      expect(tts.spoken, firstPass);
    });

    testWidgets('a switch stops playback before the next mode speaks', (
      tester,
    ) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith(practiceStory));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(tts.spoken, ['She waited for a long time.']);

      // Release read-aloud's utterance so the awaited stop can settle.
      tts.hold = false;
      tts.ordering.clear();
      await selectMode(tester, 'Listen');

      final stopAt = tts.ordering.indexOf('tts.stop');
      final speakAt = tts.ordering.indexOf('speak');
      expect(stopAt, isNonNegative);
      expect(speakAt, isNonNegative);
      expect(
        stopAt,
        lessThan(speakAt),
        reason: 'the incoming mode may only speak into a stopped controller',
      );
    });

    testWidgets('leaving Speak closes the microphone before announcing the '
        'new mode', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));
      await selectMode(tester, 'Speak');

      tts.ordering.clear();
      await selectMode(tester, 'Read');

      // The announcement channel replies asynchronously, so the previous
      // switch's announcement can still land after the clear: this switch's own
      // events are the last of each kind.
      final cancelAt = tts.ordering.lastIndexOf('stt.cancel');
      final announceAt = tts.ordering.lastIndexOf('announce');
      expect(cancelAt, isNonNegative);
      expect(announceAt, isNonNegative);
      expect(
        cancelAt,
        lessThan(announceAt),
        reason: 'the mode is announced only once the microphone is closed',
      );
    });

    testWidgets('Speak is mounted only when selected: Read and Listen never '
        'touch the microphone', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      await selectMode(tester, 'Listen');

      expect(find.byType(SpeakingView), findsNothing);
      expect(stt.attachCount, 0);
      expect(stt.initializeCount, 0);
      expect(permissions.statusCount, 0);
      expect(permissions.requestCount, 0);

      // Selecting Speak is what first touches them.
      await selectMode(tester, 'Speak');
      expect(stt.attachCount, 1);
      expect(permissions.statusCount, 1);
    });

    testWidgets('leaving the screen stops audio and releases the microphone, '
        'Speak included', (tester) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith(practiceStory));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      tts.hold = false;
      await selectMode(tester, 'Speak');
      expect(stt.attachCount, 1);

      final stopsBefore = tts.stopCount;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
      expect(stt.detachCount, 1);
      expect(stt.cancelCount, greaterThan(0));
      expect(stt.listener, isNull);
      expect(
        GetIt.I.isRegistered<TtsService>(),
        isTrue,
        reason: 'the singletons are shared and must survive the screen',
      );
    });

    testWidgets('leaving from Listen stops audio too', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));
      await selectMode(tester, 'Listen');
      final stopsBefore = tts.stopCount;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
    });

    testWidgets('a probe settling after the user left Listen speaks nothing', (
      tester,
    ) async {
      final gate = Completer<List<String>>();
      tts.holdLanguages = gate;
      await pumpScreen(tester, storyWith(practiceStory));

      await selectModeWhileWaiting(tester, 'Listen');
      expect(tts.spoken, isEmpty, reason: 'the probe has not settled yet');

      await selectModeWhileWaiting(tester, 'Read');
      // Listen is still mounted behind Read; the verdict it was waiting for
      // arrives now.
      gate.complete(const ['en-US']);
      tts.holdLanguages = null;
      await tester.pumpAndSettle();

      expect(
        tts.spoken,
        isEmpty,
        reason: 'nothing may speak into the mode the user is looking at',
      );

      // Coming back to Listen is what starts the first item.
      await selectMode(tester, 'Listen');
      expect(tts.spoken, ['She waited for a long time.']);
    });

    testWidgets('a probe settling after the user left Speak asks for no '
        'microphone', (tester) async {
      final gate = Completer<List<String>>();
      tts.holdLanguages = gate;
      await pumpScreen(tester, storyWith(practiceStory));

      await selectModeWhileWaiting(tester, 'Speak');
      expect(
        permissions.statusCount,
        0,
        reason: 'preparation is still waiting on the probe',
      );

      await selectModeWhileWaiting(tester, 'Read');
      gate.complete(const ['en-US']);
      tts.holdLanguages = null;
      // Speak stays mounted behind Read with its own spinner still turning.
      await pumpFrames(tester);

      expect(
        permissions.statusCount,
        0,
        reason: 'no permission flow may run from behind Read',
      );
      expect(permissions.requestCount, 0);

      // Coming back to Speak is what prepares it.
      await selectMode(tester, 'Speak');
      await tester.pumpAndSettle();
      expect(permissions.statusCount, 1);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('re-entering Speak before the probe settles still prepares '
        'it once', (tester) async {
      final gate = Completer<List<String>>();
      tts.holdLanguages = gate;
      await pumpScreen(tester, storyWith(practiceStory));

      // Out and back in while the first preparation is still waiting on the
      // host's probe: that attempt is now stale and prepares nothing.
      await selectModeWhileWaiting(tester, 'Speak');
      await selectModeWhileWaiting(tester, 'Read');
      await selectModeWhileWaiting(tester, 'Speak');
      expect(permissions.statusCount, 0, reason: 'the probe still holds');

      gate.complete(const ['en-US']);
      tts.holdLanguages = null;
      await tester.pumpAndSettle();

      expect(
        permissions.statusCount,
        1,
        reason: 'the abandoned attempt hands its retry on, exactly once',
      );
      expect(find.text('Record'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the app bar title is localized', (tester) async {
      await pumpScreen(
        tester,
        storyWith(practiceStory),
        locale: const Locale('zh'),
      );

      // The bar title and the body's own story heading, neither hardcoded.
      expect(find.text('故事'), findsWidgets);
      expect(find.text('Story'), findsNothing);
      // The switcher is localized with it.
      expect(modeSegment('阅读'), findsOneWidget);
      expect(modeSegment('听力'), findsOneWidget);
      expect(modeSegment('口语'), findsOneWidget);
    });
  });

  group('StoryDetailScreen playback options', () {
    testWidgets('repeat and advance carry localized labels', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));

      expect(find.byIcon(Icons.repeat_one), findsOneWidget);
      expect(find.byIcon(Icons.playlist_play), findsOneWidget);
      expect(
        find.bySemanticsLabel('Repeat each sentence twice'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Continue to the next sentence'),
        findsOneWidget,
      );
    });

    testWidgets('repeat on speaks the tapped sentence twice', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));

      await tester.tap(find.byIcon(Icons.repeat_one));
      await tester.pumpAndSettle();

      recognizersInOrder(tester)[0].onTap!();
      await tester.pumpAndSettle();

      expect(tts.spoken, [
        'She waited for a long time.',
        'She waited for a long time.',
      ]);
    });

    testWidgets('advance off keeps a tap to one sentence; advance on '
        'continues into the story', (tester) async {
      await pumpScreen(tester, storyWith(practiceStory));

      recognizersInOrder(tester)[0].onTap!();
      await tester.pumpAndSettle();
      expect(tts.spoken, ['She waited for a long time.']);

      tts.spoken.clear();
      await tester.tap(find.byIcon(Icons.playlist_play));
      await tester.pumpAndSettle();

      recognizersInOrder(tester)[0].onTap!();
      await tester.pumpAndSettle();
      expect(tts.spoken, [
        'She waited for a long time.',
        'Then it rained on the roof.',
      ]);
    });

    testWidgets('an unsupported platform disables the playback options', (
      tester,
    ) async {
      register<TtsService>(_FakeTtsService(supported: false));
      await pumpScreen(tester, storyWith(practiceStory));

      for (final icon in [Icons.repeat_one, Icons.playlist_play]) {
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull);
      }
    });
  });
}
